//
//  WebRTCCameraManager.swift
//  SlowMotionCamera
//
//  WebRTC용 카메라 관리 (기존 CameraManager와 분리)
//

import Foundation
import AVFoundation
import CoreMedia
import WebRTC

protocol WebRTCCameraManagerDelegate: AnyObject {
    func cameraDidStartRecording()
    func cameraDidStopRecording(fileURL: URL)
    func cameraDidEncounterError(_ error: Error)
}

class WebRTCCameraManager: NSObject {

    // MARK: - Properties

    weak var delegate: WebRTCCameraManagerDelegate?

    private let captureSession = AVCaptureSession()
    private var videoDevice: AVCaptureDevice?
    private var videoInput: AVCaptureDeviceInput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    // WebRTC
    private var videoCapturer: RTCVideoCapturer?
    private var videoSource: RTCVideoSource?

    // Recording (고fps 녹화용)
    private var assetWriter: AVAssetWriter?
    private var assetWriterInput: AVAssetWriterInput?
    private var isRecording = false
    private var recordingStartTime: CMTime?
    private var frameCount: Int = 0
    private var currentVideoURL: URL?

    private var recordingFPS: Int32 = Constants.Recording.defaultFPS
    private var recordingResolution: CGSize = Constants.Recording.defaultResolution
    private var webrtcFrameCount: Int = 0

    private let captureQueue = DispatchQueue(
        label: "webrtc.camera.capture",
        qos: .userInitiated
    )

    // MARK: - Preview Layer

    func getPreviewLayer() -> AVCaptureVideoPreviewLayer {
        if let existing = previewLayer {
            return existing
        }

        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        previewLayer = layer
        return layer
    }

    // MARK: - Camera Setup

    func setupCamera(fps: Int32, resolution: CGSize, videoCapturer: RTCVideoCapturer?) throws {
        self.recordingFPS = fps
        self.recordingResolution = resolution
        self.videoCapturer = videoCapturer

        // 카메라 권한 확인
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        guard authStatus == .authorized else {
            throw WebRTCCameraError.permissionDenied
        }

        captureSession.beginConfiguration()
        captureSession.sessionPreset = .inputPriority

        // 후면 카메라 찾기
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw WebRTCCameraError.deviceNotFound
        }
        self.videoDevice = camera

        // 디바이스 설정
        try camera.lockForConfiguration()

        // 고fps 지원하는 포맷 찾기
        guard let format = findBestFormat(for: camera, fps: fps, resolution: resolution) else {
            camera.unlockForConfiguration()
            throw WebRTCCameraError.unsupportedConfiguration
        }

        camera.activeFormat = format
        camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: fps)
        camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: fps)

        camera.unlockForConfiguration()

        // Input 추가
        let input = try AVCaptureDeviceInput(device: camera)
        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
            self.videoInput = input
        }

        // Output 추가
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        output.setSampleBufferDelegate(self, queue: captureQueue)
        output.alwaysDiscardsLateVideoFrames = false

        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
            self.videoOutput = output
        }

        // 비디오 회전 설정
        if let connection = output.connection(with: .video) {
            connection.videoOrientation = .portrait
        }

        captureSession.commitConfiguration()

        print("✅ WebRTC Camera setup complete: \(fps)fps @ \(Int(resolution.width))x\(Int(resolution.height))")
    }

    // MARK: - Update Video Capturer

    func updateVideoCapturer(_ videoCapturer: RTCVideoCapturer?) {
        self.videoCapturer = videoCapturer
        print("✅ Video capturer updated")
    }

    // MARK: - Format Selection

    private func findBestFormat(for device: AVCaptureDevice, fps: Int32, resolution: CGSize) -> AVCaptureDevice.Format? {
        var bestFormat: AVCaptureDevice.Format?
        var bestScore: Int = 0

        for format in device.formats {
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let width = Int(dimensions.width)
            let height = Int(dimensions.height)

            for range in format.videoSupportedFrameRateRanges {
                if range.maxFrameRate >= Double(fps) {
                    let resolutionMatch = (width >= Int(resolution.width) && height >= Int(resolution.height))
                    let score = resolutionMatch ? 100 : 0

                    if score > bestScore {
                        bestScore = score
                        bestFormat = format
                    }
                }
            }
        }

        return bestFormat
    }

    // MARK: - Session Control

    func startSession() {
        if !captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession.startRunning()
            }
        }
    }

    func stopSession() {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }

    // MARK: - Recording Control

    func startRecording() throws {
        guard !isRecording else { return }

        let filename = "recording_\(Int(Date().timeIntervalSince1970)).mov"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        assetWriter = try AVAssetWriter(url: url, fileType: .mov)

        // Portrait 모드: width와 height를 바꿔서 세로 영상으로 녹화
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: recordingResolution.height,  // Swap for portrait
            AVVideoHeightKey: recordingResolution.width,  // Swap for portrait
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 20_000_000, // 20 Mbps for better quality
                AVVideoMaxKeyFrameIntervalKey: Int(recordingFPS), // 1 keyframe per second
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: Int(recordingFPS)
            ]
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = true

        // Portrait 모드를 위한 transform 설정 (90도 회전)
        writerInput.transform = CGAffineTransform(rotationAngle: .pi / 2)

        if assetWriter?.canAdd(writerInput) == true {
            assetWriter?.add(writerInput)
            assetWriterInput = writerInput
        }

        assetWriter?.startWriting()
        recordingStartTime = nil
        isRecording = true
        frameCount = 0
        currentVideoURL = url

        print("🔴 Recording started: \(url.lastPathComponent)")
        delegate?.cameraDidStartRecording()
    }

    func stopRecording() {
        guard isRecording else { return }

        isRecording = false
        assetWriterInput?.markAsFinished()

        let url = currentVideoURL

        assetWriter?.finishWriting { [weak self] in
            guard let self = self, let finalURL = url else { return }

            print("⏹ Recording stopped: \(self.frameCount) frames")
            DispatchQueue.main.async {
                self.delegate?.cameraDidStopRecording(fileURL: finalURL)
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension WebRTCCameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // WebRTC로 프레임 전송
        sendFrameToWebRTC(sampleBuffer)

        // 녹화 중이면 파일에 저장
        if isRecording {
            recordFrame(sampleBuffer)
        }
    }

    private func sendFrameToWebRTC(_ sampleBuffer: CMSampleBuffer) {
        guard let videoCapturer = videoCapturer as? RTCCustomVideoCapturer,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let timeStampNs = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * 1_000_000_000
        let rtcPixelBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)

        let videoFrame = RTCVideoFrame(
            buffer: rtcPixelBuffer,
            rotation: ._90,  // Portrait 모드
            timeStampNs: Int64(timeStampNs)
        )

        videoCapturer.capture(videoFrame)
    }

    private func recordFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let assetWriter = assetWriter,
              let writerInput = assetWriterInput,
              assetWriter.status == .writing else {
            return
        }

        if recordingStartTime == nil {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            assetWriter.startSession(atSourceTime: timestamp)
            recordingStartTime = timestamp
        }

        if writerInput.isReadyForMoreMediaData {
            writerInput.append(sampleBuffer)
            frameCount += 1
        }
    }
}

// MARK: - RTCCustomVideoCapturer Extension

extension RTCCustomVideoCapturer {
    func capture(_ videoFrame: RTCVideoFrame) {
        // 부모 클래스의 delegate에 프레임 전달
        self.delegate?.capturer(self, didCapture: videoFrame)
    }
}

// MARK: - WebRTCCameraError

enum WebRTCCameraError: LocalizedError {
    case permissionDenied
    case deviceNotFound
    case unsupportedConfiguration
    case recordingFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "카메라 권한이 없습니다"
        case .deviceNotFound:
            return "카메라를 찾을 수 없습니다"
        case .unsupportedConfiguration:
            return "지원하지 않는 카메라 설정입니다"
        case .recordingFailed:
            return "녹화에 실패했습니다"
        }
    }
}

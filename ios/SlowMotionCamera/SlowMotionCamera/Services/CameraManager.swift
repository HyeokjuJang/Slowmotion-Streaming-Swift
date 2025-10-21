//
//  CameraManager.swift
//  SlowMotionCamera
//
//  AVFoundation을 사용한 고fps 카메라 녹화 관리
//

import Foundation
import AVFoundation
import CoreMedia
import UIKit

protocol CameraManagerDelegate: AnyObject {
    func cameraDidStartRecording()
    func cameraDidStopRecording(fileURL: URL)
    func cameraDidCaptureFrame(_ sampleBuffer: CMSampleBuffer)
    func cameraDidEncounterError(_ error: Error)
}

class CameraManager: NSObject {

    // MARK: - Properties

    weak var delegate: CameraManagerDelegate?

    private let captureSession = AVCaptureSession()
    private var videoDevice: AVCaptureDevice?
    private var videoInput: AVCaptureDeviceInput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    private var assetWriter: AVAssetWriter?
    private var assetWriterInput: AVAssetWriterInput?
    private var assetWriterAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    private var isRecording = false
    private var recordingStartTime: CMTime?
    private var frameCount: Int = 0

    private var recordingFPS: Int32 = Constants.Recording.defaultFPS
    private var recordingResolution: CGSize = Constants.Recording.defaultResolution

    private let captureQueue = DispatchQueue(
        label: Constants.Performance.captureQueueLabel,
        qos: Constants.Performance.captureQueueQoS
    )

    private var currentVideoURL: URL?

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

    func setupCamera(fps: Int32, resolution: CGSize) throws {
        self.recordingFPS = fps
        self.recordingResolution = resolution

        // 카메라 권한 확인
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        guard authStatus == .authorized else {
            throw CameraError.permissionDenied
        }

        // 세션 설정 시작
        captureSession.beginConfiguration()

        // SessionPreset을 inputPriority로 설정 - 디바이스 포맷을 우선시!
        captureSession.sessionPreset = .inputPriority

        // 기존 입력 제거
        if let existingInput = videoInput {
            captureSession.removeInput(existingInput)
        }

        // 비디오 디바이스 찾기 (후면 카메라)
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraError.deviceNotFound
        }

        videoDevice = device

        // 디바이스 설정 (fps 및 해상도)
        try configureDevice(device: device, fps: fps, resolution: resolution)

        // 비디오 입력 추가
        let input = try AVCaptureDeviceInput(device: device)
        guard captureSession.canAddInput(input) else {
            throw CameraError.cannotAddInput
        }
        captureSession.addInput(input)
        videoInput = input

        // 비디오 출력 추가
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: captureQueue)
        output.alwaysDiscardsLateVideoFrames = false  // 고fps에서는 프레임 드롭 방지!
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        guard captureSession.canAddOutput(output) else {
            throw CameraError.cannotAddOutput
        }
        captureSession.addOutput(output)
        videoOutput = output

        // 비디오 연결 설정
        if let connection = output.connection(with: .video) {
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .auto
            }
        }

        captureSession.commitConfiguration()

        print("✅ Camera setup complete: \(fps)fps @ \(Int(resolution.width))x\(Int(resolution.height))")
    }

    /// 디바이스 설정 (fps 및 해상도)
    private func configureDevice(device: AVCaptureDevice, fps: Int32, resolution: CGSize) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        // 지원하는 포맷 찾기
        guard let format = findBestFormat(for: device, fps: fps, resolution: resolution) else {
            throw CameraError.formatNotSupported
        }

        device.activeFormat = format

        // FPS 설정
        let duration = CMTimeMake(value: 1, timescale: fps)
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration

        print("📹 Selected format: \(format)")
        print("📹 FPS set to: \(fps)")
    }

    /// 최적의 카메라 포맷 찾기
    private func findBestFormat(
        for device: AVCaptureDevice,
        fps: Int32,
        resolution: CGSize
    ) -> AVCaptureDevice.Format? {
        var bestFormat: AVCaptureDevice.Format?

        print("🔍 Looking for format: \(Int(resolution.width))x\(Int(resolution.height)) @ \(fps)fps")

        for format in device.formats {
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let formatResolution = CGSize(width: Int(dimensions.width), height: Int(dimensions.height))

            // 해상도 확인
            guard formatResolution.width >= resolution.width &&
                  formatResolution.height >= resolution.height else {
                continue
            }

            // FPS 지원 확인
            for range in format.videoSupportedFrameRateRanges {
                if range.maxFrameRate >= Double(fps) && range.minFrameRate <= Double(fps) {
                    print("✓ Found compatible format: \(Int(dimensions.width))x\(Int(dimensions.height)) FPS range: \(range.minFrameRate)-\(range.maxFrameRate)")

                    // 정확히 일치하는 해상도를 찾거나, 더 나은 포맷 선택
                    if bestFormat == nil {
                        bestFormat = format
                    } else {
                        let bestDimensions = CMVideoFormatDescriptionGetDimensions(bestFormat!.formatDescription)
                        if dimensions.width < bestDimensions.width {
                            bestFormat = format
                        }
                    }
                }
            }
        }

        if let best = bestFormat {
            let dims = CMVideoFormatDescriptionGetDimensions(best.formatDescription)
            print("✅ Selected format: \(Int(dims.width))x\(Int(dims.height))")
        } else {
            print("❌ No compatible format found!")
        }

        return bestFormat
    }

    // MARK: - Session Control

    func startSession() {
        if !captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession.startRunning()
                print("▶️ Capture session started")
            }
        }
    }

    func stopSession() {
        if captureSession.isRunning {
            captureSession.stopRunning()
            print("⏹ Capture session stopped")
        }
    }

    // MARK: - Recording Control

    func startRecording() throws {
        guard !isRecording else {
            print("⚠️ Already recording")
            return
        }

        // 녹화 파일 URL 생성
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingsDir = documentsPath.appendingPathComponent(Constants.Storage.recordingsDirectory)

        // 디렉토리 생성
        try? FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)

        let filename = "video_\(Int(Date().timeIntervalSince1970)).\(Constants.Recording.fileExtension)"
        let videoURL = recordingsDir.appendingPathComponent(filename)
        currentVideoURL = videoURL

        // AVAssetWriter 설정
        assetWriter = try AVAssetWriter(outputURL: videoURL, fileType: .mov)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: recordingResolution.width,
            AVVideoHeightKey: recordingResolution.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 10_000_000, // 10 Mbps
                AVVideoExpectedSourceFrameRateKey: recordingFPS,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]

        assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        assetWriterInput?.expectsMediaDataInRealTime = true

        guard let assetWriter = assetWriter,
              let assetWriterInput = assetWriterInput,
              assetWriter.canAdd(assetWriterInput) else {
            throw CameraError.cannotCreateWriter
        }

        assetWriter.add(assetWriterInput)

        // Pixel buffer adaptor 설정
        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: recordingResolution.width,
            kCVPixelBufferHeightKey as String: recordingResolution.height
        ]

        assetWriterAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: assetWriterInput,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )

        // 녹화 시작
        assetWriter.startWriting()
        recordingStartTime = nil
        frameCount = 0
        isRecording = true

        print("🔴 Recording started: \(filename)")
        print("📹 Recording FPS: \(recordingFPS)")
        print("📹 Recording Resolution: \(Int(recordingResolution.width))x\(Int(recordingResolution.height))")

        DispatchQueue.main.async {
            self.delegate?.cameraDidStartRecording()
        }
    }

    func stopRecording() {
        guard isRecording else {
            print("⚠️ Not recording")
            return
        }

        isRecording = false

        assetWriterInput?.markAsFinished()

        assetWriter?.finishWriting { [weak self] in
            guard let self = self,
                  let videoURL = self.currentVideoURL else {
                return
            }

            print("⏹ Recording stopped: \(videoURL.lastPathComponent)")
            print("📊 Total frames: \(self.frameCount)")

            DispatchQueue.main.async {
                self.delegate?.cameraDidStopRecording(fileURL: videoURL)
            }

            // 리소스 정리
            self.assetWriter = nil
            self.assetWriterInput = nil
            self.assetWriterAdaptor = nil
            self.recordingStartTime = nil
        }
    }

    // MARK: - Disk Space Check

    func checkDiskSpace() -> Bool {
        guard let systemAttributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let freeSpace = systemAttributes[.systemFreeSize] as? UInt64 else {
            return false
        }

        return freeSpace >= Constants.Storage.minimumFreeSpace
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // 프레임 캡처 콜백 (스트리밍용)
        delegate?.cameraDidCaptureFrame(sampleBuffer)

        // 녹화 중이면 파일에 저장
        if isRecording {
            recordFrame(sampleBuffer)
        }
    }

    private func recordFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let assetWriter = assetWriter,
              let assetWriterInput = assetWriterInput,
              let assetWriterAdaptor = assetWriterAdaptor else {
            return
        }

        // 첫 프레임에서 세션 시작
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if recordingStartTime == nil {
            recordingStartTime = presentationTime
            assetWriter.startSession(atSourceTime: presentationTime)
        }

        // 입력이 준비되면 프레임 추가
        if assetWriterInput.isReadyForMoreMediaData {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                return
            }

            let success = assetWriterAdaptor.append(pixelBuffer, withPresentationTime: presentationTime)

            if success {
                frameCount += 1
                // 100프레임마다 로그 출력
                if frameCount % 100 == 0 {
                    print("📊 Frames recorded: \(frameCount)")
                }
            } else if let error = assetWriter.error {
                print("❌ Failed to append frame: \(error)")
                DispatchQueue.main.async {
                    self.delegate?.cameraDidEncounterError(error)
                }
            }
        } else {
            // 입력이 준비되지 않아 프레임 드롭됨
            if frameCount % 100 == 0 {
                print("⚠️ Frame dropped: writer not ready")
            }
        }
    }
}

// MARK: - Camera Errors

enum CameraError: LocalizedError {
    case permissionDenied
    case deviceNotFound
    case cannotAddInput
    case cannotAddOutput
    case formatNotSupported
    case cannotCreateWriter

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "카메라 권한이 거부되었습니다."
        case .deviceNotFound:
            return "카메라를 찾을 수 없습니다."
        case .cannotAddInput:
            return "카메라 입력을 추가할 수 없습니다."
        case .cannotAddOutput:
            return "비디오 출력을 추가할 수 없습니다."
        case .formatNotSupported:
            return "요청한 포맷을 지원하지 않습니다."
        case .cannotCreateWriter:
            return "비디오 writer를 생성할 수 없습니다."
        }
    }
}

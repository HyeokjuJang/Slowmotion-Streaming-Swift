//
//  WebRTCViewController.swift
//  SlowMotionCamera
//
//  WebRTC 기반 카메라 뷰 컨트롤러
//

import Foundation
import SwiftUI
import AVFoundation
import WebRTC

class WebRTCViewController: ObservableObject {

    // MARK: - Published Properties

    @Published var connectionStatus: String = "연결 대기중"
    @Published var recordingStatus: String = "대기중"
    @Published var isRecording: Bool = false
    @Published var previewLayer: AVCaptureVideoPreviewLayer?
    @Published var isCameraReady: Bool = false

    // MARK: - Dependencies

    let settings: CameraSettings
    let state: RecordingStateManager

    // MARK: - Managers

    private let webSocketManager = WebSocketManager()
    private let webRTCManager = WebRTCManager()
    private var webRTCCameraManager: WebRTCCameraManager?
    private var cameraManager: CameraManager?
    private var streamingManager: StreamingManager?

    // MARK: - Initialization

    init(settings: CameraSettings, state: RecordingStateManager) {
        self.settings = settings
        self.state = state

        webSocketManager.delegate = self
        webRTCManager.delegate = self

        // 카메라는 연결 시점에 설정됨
    }

    // MARK: - Setup

    private func setupCamera() {
        guard webRTCCameraManager == nil && cameraManager == nil else {
            print("⚠️ Camera already set up, skipping")
            return
        }

        do {
            if settings.streamingMode == .webRTC {
                // WebRTC 모드: WebRTCCameraManager 사용
                print("🎥 Setting up WebRTC camera mode...")

                let webRTCCamera = WebRTCCameraManager()
                webRTCCamera.delegate = self
                self.webRTCCameraManager = webRTCCamera

                // WebRTC Peer Connection 설정
                webRTCManager.setupPeerConnection()

                // Video Capturer 생성 (스트리밍용 FPS 정보)
                let capturer = webRTCManager.setupCapturer(
                    fps: Constants.WebRTC.streamingFPS,
                    width: Int32(Constants.WebRTC.streamingResolution.width),
                    height: Int32(Constants.WebRTC.streamingResolution.height)
                )

                // 카메라 설정 (녹화용 fps)
                try webRTCCamera.setupCamera(
                    fps: settings.recordingFPS,
                    resolution: settings.recordingResolution,
                    videoCapturer: capturer,
                    webrtcStreamingFPS: Constants.WebRTC.streamingFPS
                )

                // Preview layer 설정 (메인 스레드에서)
                let layer = webRTCCamera.getPreviewLayer()

                DispatchQueue.main.async {
                    self.previewLayer = layer
                    self.isCameraReady = true
                }
            } else {
                // WebSocket 모드: CameraManager + StreamingManager 사용
                print("🎥 Setting up WebSocket camera mode...")

                let camera = CameraManager()
                camera.delegate = self
                self.cameraManager = camera

                // 스트리밍 매니저 초기화
                self.streamingManager = StreamingManager(
                    webSocketManager: webSocketManager,
                    settings: settings
                )

                // 카메라 설정
                try camera.setupCamera(
                    fps: settings.recordingFPS,
                    resolution: settings.recordingResolution
                )

                // Preview layer 설정 (메인 스레드에서)
                let layer = camera.getPreviewLayer()

                DispatchQueue.main.async {
                    self.previewLayer = layer
                    self.isCameraReady = true
                }
            }
        } catch {
            print("❌ Failed to setup camera: \(error)")
            connectionStatus = "카메라 설정 실패"
        }
    }

    // MARK: - Connection

    func connect() {
        guard !settings.serverURL.isEmpty else {
            connectionStatus = "서버 URL을 설정해주세요"
            return
        }

        // 카메라 설정 (최초 1회만)
        setupCamera()

        connectionStatus = "연결중..."
        webSocketManager.connect(to: settings.serverURL)
    }

    func disconnect() {
        webSocketManager.disconnect()
        webRTCManager.disconnect()
        webRTCCameraManager?.stopSession()
        cameraManager?.stopSession()
        connectionStatus = "연결 해제됨"
    }

    // MARK: - Camera Control

    func startSession() {
        if settings.streamingMode == .webRTC {
            webRTCCameraManager?.startSession()
        } else {
            cameraManager?.startSession()
            streamingManager?.resetFrameCounter()
        }
    }

    func stopSession() {
        if settings.streamingMode == .webRTC {
            webRTCCameraManager?.stopSession()
        } else {
            cameraManager?.stopSession()
        }
    }

    // MARK: - Recording Control

    func startRecording() {
        guard !isRecording else { return }

        do {
            if settings.streamingMode == .webRTC {
                try webRTCCameraManager?.startRecording()
            } else {
                try cameraManager?.startRecording()
            }
            isRecording = true
            recordingStatus = "녹화중"
        } catch {
            print("❌ Failed to start recording: \(error)")
            recordingStatus = "녹화 실패"
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        if settings.streamingMode == .webRTC {
            webRTCCameraManager?.stopRecording()
        } else {
            cameraManager?.stopRecording()
        }
        isRecording = false
        recordingStatus = "대기중"
    }

    // MARK: - Preview Layer

    func getPreviewLayer() -> AVCaptureVideoPreviewLayer? {
        if settings.streamingMode == .webRTC {
            return webRTCCameraManager?.getPreviewLayer()
        } else {
            return cameraManager?.getPreviewLayer()
        }
    }
}

// MARK: - WebSocketManagerDelegate

extension WebRTCViewController: WebSocketManagerDelegate {

    func webSocketDidConnect() {
        connectionStatus = "연결됨"

        if settings.streamingMode == .webRTC {
            // WebRTC 모드: WebRTC Peer Connection 설정

            // WebRTC Peer Connection 재설정 (재연결 대비)
            webRTCManager.setupPeerConnection()

            // Video Capturer 재생성 및 업데이트 (재연결 시 videoSource가 새로 생성되므로)
            if webRTCCameraManager != nil {
                let capturer = webRTCManager.setupCapturer(
                    fps: Constants.WebRTC.streamingFPS,
                    width: Int32(Constants.WebRTC.streamingResolution.width),
                    height: Int32(Constants.WebRTC.streamingResolution.height)
                )
                webRTCCameraManager?.updateVideoCapturer(capturer)
                webRTCCameraManager?.updateWebRTCStreamingFPS(Constants.WebRTC.streamingFPS)
            }

            // WebRTC Offer 생성
            webRTCManager.createOffer()
        }
        // WebSocket 모드: WebRTC 설정 스킵, 스트리밍 매니저만 사용

        // 카메라 세션 시작
        startSession()
    }

    func webSocketDidDisconnect(error: Error?) {
        connectionStatus = "연결 끊김"
        if let error = error {
            print("❌ WebSocket error: \(error)")
        }
    }

    func webSocketDidReceiveCommand(_ command: String) {
        print("📥 Command received: \(command)")

        switch command {
        case "start":
            startRecording()
        case "stop":
            stopRecording()
        case "reconnect":
            print("🔄 Reconnection requested - restarting WebRTC connection")
            reconnectWebRTC()
        default:
            print("⚠️ Unknown command: \(command)")
        }
    }

    private func reconnectWebRTC() {
        print("🔄 Starting WebRTC reconnection...")

        // 1. 기존 peer connection 종료
        webRTCManager.disconnect()

        // 2. 새 peer connection 설정
        webRTCManager.setupPeerConnection()

        // 3. Video Capturer 재생성
        if webRTCCameraManager != nil {
            let capturer = webRTCManager.setupCapturer(
                fps: Constants.WebRTC.streamingFPS,
                width: Int32(Constants.WebRTC.streamingResolution.width),
                height: Int32(Constants.WebRTC.streamingResolution.height)
            )
            webRTCCameraManager?.updateVideoCapturer(capturer)
        }

        // 4. 새로운 offer 생성
        webRTCManager.createOffer()

        print("✅ WebRTC reconnection initiated")
    }

    func webSocketDidReceiveSignaling(_ message: SignalingMessage) {
        print("📡 Signaling received: \(message.type)")

        switch message.type {
        case "answer":
            // Answer 처리
            if let sdp = message.sdp {
                let answer = RTCSessionDescription(type: .answer, sdp: sdp)
                webRTCManager.handleAnswer(answer)
            }

        case "ice":
            // ICE Candidate 처리
            if let candidate = message.candidate {
                let iceCandidate = RTCIceCandidate(
                    sdp: candidate.candidate,
                    sdpMLineIndex: candidate.sdpMLineIndex,
                    sdpMid: candidate.sdpMid
                )
                webRTCManager.addIceCandidate(iceCandidate)
            }

        default:
            print("⚠️ Unknown signaling type: \(message.type)")
        }
    }
}

// MARK: - WebRTCManagerDelegate

extension WebRTCViewController: WebRTCManagerDelegate {

    func webRTCManager(_ manager: WebRTCManager, didGenerateOffer sdp: RTCSessionDescription) {
        print("📤 Sending offer...")

        let message = SignalingMessage(
            type: "offer",
            sdp: sdp.sdp,
            candidate: nil
        )

        webSocketManager.sendSignaling(message)
    }

    func webRTCManager(_ manager: WebRTCManager, didGenerateIceCandidate candidate: RTCIceCandidate) {
        print("📤 Sending ICE candidate...")

        let iceCandidate = IceCandidate(
            candidate: candidate.sdp,
            sdpMLineIndex: candidate.sdpMLineIndex,
            sdpMid: candidate.sdpMid
        )

        let message = SignalingMessage(
            type: "ice",
            sdp: nil,
            candidate: iceCandidate
        )

        webSocketManager.sendSignaling(message)
    }

    func webRTCManager(_ manager: WebRTCManager, didChangeConnectionState state: RTCIceConnectionState) {
        print("🔗 Connection state changed: \(state.rawValue)")

        DispatchQueue.main.async {
            switch state {
            case .connected:
                self.connectionStatus = "WebRTC 연결됨"
            case .disconnected:
                self.connectionStatus = "WebRTC 연결 끊김"
            case .failed:
                self.connectionStatus = "WebRTC 연결 실패"
            default:
                break
            }
        }
    }
}

// MARK: - CameraManagerDelegate & WebRTCCameraManagerDelegate

extension WebRTCViewController: CameraManagerDelegate, WebRTCCameraManagerDelegate {

    func cameraDidStartRecording() {
        DispatchQueue.main.async {
            self.state.isRecording = true
            self.recordingStatus = "녹화중"
        }
    }

    func cameraDidStopRecording(fileURL: URL) {
        DispatchQueue.main.async {
            self.state.isRecording = false
            self.recordingStatus = "업로드중..."

            // 비디오 업로드
            self.uploadVideo(fileURL: fileURL)
        }
    }

    func cameraDidCaptureFrame(_ sampleBuffer: CMSampleBuffer) {
        // WebSocket 스트리밍: 프레임을 StreamingManager에 전달
        streamingManager?.processFrame(sampleBuffer, recordingFPS: settings.recordingFPS)
    }

    func cameraDidEncounterError(_ error: Error) {
        print("❌ Camera error: \(error)")
        DispatchQueue.main.async {
            self.recordingStatus = "오류 발생"
        }
    }

    // MARK: - Video Upload

    private func uploadVideo(fileURL: URL) {
        guard let uploadURL = URL(string: settings.autoGeneratedUploadURL) else {
            print("❌ Invalid upload URL")
            recordingStatus = "업로드 URL 오류"
            return
        }

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // 파일 데이터 추가
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"video\"; filename=\"\(fileURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: video/quicktime\r\n\r\n".data(using: .utf8)!)

        if let fileData = try? Data(contentsOf: fileURL) {
            body.append(fileData)
            body.append("\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Upload failed: \(error)")
                    self?.recordingStatus = "업로드 실패"
                } else {
                    print("✅ Upload successful")
                    self?.recordingStatus = "업로드 완료"

                    // 임시 파일 삭제
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
        }.resume()
    }
}

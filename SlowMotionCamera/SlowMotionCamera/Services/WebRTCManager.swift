//
//  WebRTCManager.swift
//  SlowMotionCamera
//
//  WebRTC Peer Connection 관리
//

import Foundation
import WebRTC

protocol WebRTCManagerDelegate: AnyObject {
    func webRTCManager(_ manager: WebRTCManager, didGenerateOffer sdp: RTCSessionDescription)
    func webRTCManager(_ manager: WebRTCManager, didGenerateIceCandidate candidate: RTCIceCandidate)
    func webRTCManager(_ manager: WebRTCManager, didChangeConnectionState state: RTCIceConnectionState)
}

class WebRTCManager: NSObject {

    // MARK: - Properties

    weak var delegate: WebRTCManagerDelegate?

    private let peerConnectionFactory: RTCPeerConnectionFactory
    private var peerConnection: RTCPeerConnection?
    private var videoCapturer: RTCVideoCapturer?
    private var localVideoTrack: RTCVideoTrack?
    private var localAudioTrack: RTCAudioTrack?
    private var videoSource: RTCVideoSource?

    private let rtcAudioSession = RTCAudioSession.sharedInstance()

    // MARK: - Initialization

    override init() {
        // WebRTC 초기화
        RTCInitializeSSL()

        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()

        self.peerConnectionFactory = RTCPeerConnectionFactory(
            encoderFactory: encoderFactory,
            decoderFactory: decoderFactory
        )

        super.init()

        setupAudioSession()
    }

    deinit {
        disconnect()
        RTCCleanupSSL()
    }

    // MARK: - Audio Session Setup

    private func setupAudioSession() {
        rtcAudioSession.lockForConfiguration()
        do {
            try rtcAudioSession.setCategory(.playAndRecord)
            try rtcAudioSession.setMode(.videoChat)
            try rtcAudioSession.setActive(true)
        } catch {
            print("❌ Failed to setup audio session: \(error)")
        }
        rtcAudioSession.unlockForConfiguration()
    }

    // MARK: - Peer Connection Setup

    func setupPeerConnection() {
        // 기존 연결이 있으면 먼저 정리
        if let existingConnection = peerConnection {
            existingConnection.close()
            print("🔄 Closing existing peer connection")
        }

        let config = RTCConfiguration()
        config.iceServers = [
            RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"]),
            RTCIceServer(urlStrings: ["stun:stun1.l.google.com:19302"])
        ]
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
        )

        let peerConnection = peerConnectionFactory.peerConnection(
            with: config,
            constraints: constraints,
            delegate: self
        )

        self.peerConnection = peerConnection

        // Video track 추가
        createVideoTrack()

        print("✅ Peer connection created")
    }

    // MARK: - Video Track Creation

    private func createVideoTrack() {
        let videoSource = peerConnectionFactory.videoSource()
        self.videoSource = videoSource

        let videoTrack = peerConnectionFactory.videoTrack(with: videoSource, trackId: "video0")
        self.localVideoTrack = videoTrack

        // Transceiver로 추가하여 방향을 명시적으로 설정
        let transceiverInit = RTCRtpTransceiverInit()
        transceiverInit.direction = .sendOnly
        transceiverInit.streamIds = ["stream0"]  // Stream ID 명시

        peerConnection?.addTransceiver(with: videoTrack, init: transceiverInit)

        print("✅ Video track added to peer connection (sendOnly)")
    }

    // MARK: - Video Capturer Setup

    func setupCapturer(fps: Int32, width: Int32, height: Int32) -> RTCVideoCapturer? {
        guard let videoSource = self.videoSource else {
            print("❌ Video source not initialized")
            return nil
        }

        let capturer = RTCCustomVideoCapturer(delegate: videoSource)
        self.videoCapturer = capturer

        print("✅ Custom video capturer created (\(width)x\(height) @ \(fps)fps)")
        return capturer
    }

    // MARK: - Offer/Answer

    func createOffer() {
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "false",
                "OfferToReceiveVideo": "false"
            ],
            optionalConstraints: nil
        )

        peerConnection?.offer(for: constraints) { [weak self] sdp, error in
            guard let self = self, let sdp = sdp else {
                print("❌ Failed to create offer: \(error?.localizedDescription ?? "unknown")")
                return
            }

            self.peerConnection?.setLocalDescription(sdp) { error in
                if let error = error {
                    print("❌ Failed to set local description: \(error)")
                    return
                }

                print("✅ Offer created and set as local description")
                self.delegate?.webRTCManager(self, didGenerateOffer: sdp)
            }
        }
    }

    func handleAnswer(_ sdp: RTCSessionDescription) {
        peerConnection?.setRemoteDescription(sdp) { error in
            if let error = error {
                print("❌ Failed to set remote description: \(error)")
            } else {
                print("✅ Answer set as remote description")
            }
        }
    }

    func addIceCandidate(_ candidate: RTCIceCandidate) {
        peerConnection?.add(candidate)
        print("✅ ICE candidate added")
    }

    // MARK: - Disconnect

    func disconnect() {
        peerConnection?.close()
        peerConnection = nil
        videoCapturer = nil
        localVideoTrack = nil
        videoSource = nil

        print("⚪️ WebRTC disconnected")
    }
}

// MARK: - RTCPeerConnectionDelegate

extension WebRTCManager: RTCPeerConnectionDelegate {

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        print("🔵 Signaling state changed: \(stateChanged.rawValue)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        print("📹 Stream added")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        print("📹 Stream removed")
    }

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        print("🔄 Should negotiate")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        print("🧊 ICE connection state: \(newState.rawValue)")
        delegate?.webRTCManager(self, didChangeConnectionState: newState)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        print("🧊 ICE gathering state: \(newState.rawValue)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        print("🧊 ICE candidate generated")
        delegate?.webRTCManager(self, didGenerateIceCandidate: candidate)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        print("🧊 ICE candidates removed")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        print("📡 Data channel opened")
    }
}

// MARK: - Custom Video Capturer

class RTCCustomVideoCapturer: RTCVideoCapturer {
    // 이 클래스는 AVCaptureSession의 프레임을 WebRTC로 전달하는 역할
}

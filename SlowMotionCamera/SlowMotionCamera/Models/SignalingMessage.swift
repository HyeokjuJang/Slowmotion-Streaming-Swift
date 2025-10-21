//
//  SignalingMessage.swift
//  SlowMotionCamera
//
//  WebRTC 시그널링 메시지 모델
//

import Foundation

/// WebRTC 시그널링 메시지 타입
enum SignalingMessageType: String, Codable {
    case offer
    case answer
    case iceCandidate = "ice"
    case ready
}

/// WebRTC 시그널링 메시지
struct SignalingMessage: Codable {
    let type: String
    let sdp: String?
    let candidate: IceCandidate?

    enum CodingKeys: String, CodingKey {
        case type
        case sdp
        case candidate
    }
}

/// ICE Candidate 정보
struct IceCandidate: Codable {
    let candidate: String
    let sdpMLineIndex: Int32
    let sdpMid: String?

    enum CodingKeys: String, CodingKey {
        case candidate
        case sdpMLineIndex
        case sdpMid
    }
}

/// WebRTC 제어 명령
struct WebRTCCommand: Codable {
    let command: String
    let timestamp: Double?
}

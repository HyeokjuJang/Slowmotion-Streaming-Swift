//
//  Constants.swift
//  SlowMotionCamera
//
//  상수 및 설정값 정의
//

import Foundation
import CoreGraphics

struct Constants {

    // MARK: - 기본 녹화 설정
    struct Recording {
        static let defaultFPS: Int32 = 120
        static let defaultResolution = CGSize(width: 1920, height: 1080)
        static let videoCodec = "avc1" // H.264
        static let fileExtension = "mov"

        // 지원 FPS 목록
        static let supportedFPS: [Int32] = [60, 120, 240]

        // 지원 해상도 목록
        static let supportedResolutions: [String: CGSize] = [
            "720p": CGSize(width: 1280, height: 720),
            "1080p": CGSize(width: 1920, height: 1080),
            "4K": CGSize(width: 3840, height: 2160)
        ]
    }

    // MARK: - 스트리밍 설정
    struct Streaming {
        static let defaultFPS: Int32 = 15
        static let defaultResolution = CGSize(width: 640, height: 360)  // 360p for lowest latency
        static let jpegQuality: CGFloat = 0.4  // 40% for faster encoding

        // 지원 스트리밍 FPS
        static let supportedFPS: [Int32] = [10, 15, 30]

        // 지원 스트리밍 해상도
        static let supportedResolutions: [String: CGSize] = [
            "360p": CGSize(width: 640, height: 360),   // 추가: 더 빠름
            "480p": CGSize(width: 640, height: 480),   // 수정: 854 → 640
            "720p": CGSize(width: 1280, height: 720)
        ]
    }

    // MARK: - 네트워크 설정
    struct Network {
        static let wsReconnectDelay: TimeInterval = 5.0
        static let wsMaxReconnectAttempts = 5
        static let wsTimeout: TimeInterval = 30.0
        static let uploadTimeout: TimeInterval = 300.0
        static let uploadMaxRetries = 3
    }

    // MARK: - 성능 설정
    struct Performance {
        static let captureQueueLabel = "camera.capture"
        static let processingQueueLabel = "image.processing"
        static let networkQueueLabel = "network"
        static let captureQueueQoS: DispatchQoS = .userInitiated
        static let processingQueueQoS: DispatchQoS = .userInitiated
        static let networkQueueQoS: DispatchQoS = .utility
    }

    // MARK: - 저장 설정
    struct Storage {
        static let minimumFreeSpace: UInt64 = 1_073_741_824 // 1GB in bytes
        static let recordingsDirectory = "Recordings"
    }

    // MARK: - UI 설정
    struct UI {
        static let statusUpdateInterval: TimeInterval = 0.1
        static let previewAspectRatio: CGFloat = 16.0 / 9.0
    }
}

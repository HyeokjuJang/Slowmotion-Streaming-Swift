//
//  RecordingState.swift
//  SlowMotionCamera
//
//  앱의 녹화 상태 관리 모델
//

import Foundation

/// 앱의 현재 상태
enum AppState: String {
    case idle = "idle"                  // 초기 상태, 연결 전
    case connecting = "connecting"      // 서버 연결 시도 중
    case waiting = "waiting"            // 서버 연결됨, 명령 대기 중
    case recording = "recording"        // 녹화 중
    case uploading = "uploading"        // 업로드 중
    case error = "error"                // 오류 상태

    var displayText: String {
        switch self {
        case .idle:
            return "대기"
        case .connecting:
            return "연결 중"
        case .waiting:
            return "서버 대기 중"
        case .recording:
            return "녹화 중"
        case .uploading:
            return "업로드 중"
        case .error:
            return "오류"
        }
    }

    var emoji: String {
        switch self {
        case .idle:
            return "⚪️"
        case .connecting:
            return "🔵"
        case .waiting:
            return "🟡"
        case .recording:
            return "🔴"
        case .uploading:
            return "🟢"
        case .error:
            return "⚠️"
        }
    }
}

/// 앱 전역 상태 관리
class RecordingStateManager: ObservableObject {

    // MARK: - Published Properties

    @Published var currentState: AppState = .idle
    @Published var errorMessage: String?
    @Published var isConnected: Bool = false

    // 녹화 관련 상태
    @Published var isRecording: Bool = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var frameCount: Int = 0

    // 업로드 관련 상태
    @Published var uploadProgress: Double = 0.0
    @Published var isUploading: Bool = false

    // 네트워크 상태
    @Published var reconnectAttempts: Int = 0
    @Published var lastConnectedTime: Date?

    // MARK: - State Management

    func setState(_ state: AppState, error: String? = nil) {
        DispatchQueue.main.async {
            self.currentState = state
            self.errorMessage = error

            // 상태 변경에 따른 플래그 업데이트
            switch state {
            case .idle, .connecting:
                self.isConnected = false
                self.isRecording = false
                self.isUploading = false
            case .waiting:
                self.isConnected = true
                self.isRecording = false
                self.isUploading = false
                self.lastConnectedTime = Date()
            case .recording:
                self.isConnected = true
                self.isRecording = true
                self.isUploading = false
            case .uploading:
                self.isConnected = true
                self.isRecording = false
                self.isUploading = true
            case .error:
                self.isRecording = false
                self.isUploading = false
            }
        }
    }

    func resetRecordingStats() {
        DispatchQueue.main.async {
            self.recordingDuration = 0
            self.frameCount = 0
        }
    }

    func updateRecordingStats(duration: TimeInterval, frames: Int) {
        DispatchQueue.main.async {
            self.recordingDuration = duration
            self.frameCount = frames
        }
    }

    func updateUploadProgress(_ progress: Double) {
        DispatchQueue.main.async {
            self.uploadProgress = progress
        }
    }

    func incrementReconnectAttempt() {
        DispatchQueue.main.async {
            self.reconnectAttempts += 1
        }
    }

    func resetReconnectAttempts() {
        DispatchQueue.main.async {
            self.reconnectAttempts = 0
        }
    }

    // MARK: - Utility

    var statusDisplayText: String {
        var text = "\(currentState.emoji) \(currentState.displayText)"

        if isRecording {
            let minutes = Int(recordingDuration) / 60
            let seconds = Int(recordingDuration) % 60
            text += " (\(String(format: "%02d:%02d", minutes, seconds)))"
        }

        if isUploading {
            text += " (\(Int(uploadProgress * 100))%)"
        }

        return text
    }
}

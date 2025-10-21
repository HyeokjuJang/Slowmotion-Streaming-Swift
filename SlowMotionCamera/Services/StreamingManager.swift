//
//  StreamingManager.swift
//  SlowMotionCamera
//
//  비디오 스트리밍 관리 (프레임 다운샘플링 및 전송)
//

import Foundation
import AVFoundation
import CoreMedia

class StreamingManager {

    // MARK: - Properties

    private let webSocketManager: WebSocketManager
    private let imageProcessor = ImageProcessor.shared

    private var streamingFPS: Int32
    private var streamingResolution: CGSize
    private var jpegQuality: CGFloat

    private var frameCounter: Int = 0
    private let processingQueue = DispatchQueue(
        label: Constants.Performance.processingQueueLabel,
        qos: Constants.Performance.processingQueueQoS
    )

    // MARK: - Initialization

    init(webSocketManager: WebSocketManager, settings: CameraSettings) {
        self.webSocketManager = webSocketManager
        self.streamingFPS = settings.streamingFPS
        self.streamingResolution = settings.streamingResolution
        self.jpegQuality = settings.jpegQuality
    }

    // MARK: - Configuration

    func updateSettings(fps: Int32, resolution: CGSize, quality: CGFloat) {
        streamingFPS = fps
        streamingResolution = resolution
        jpegQuality = quality
    }

    func resetFrameCounter() {
        frameCounter = 0
    }

    // MARK: - Frame Processing

    /// 프레임 처리 및 스트리밍
    /// - Parameters:
    ///   - sampleBuffer: 카메라에서 캡처한 프레임
    ///   - recordingFPS: 현재 녹화 fps
    func processFrame(_ sampleBuffer: CMSampleBuffer, recordingFPS: Int32) {
        frameCounter += 1

        // 다운샘플링 확인
        guard imageProcessor.shouldStreamFrame(
            currentFrame: frameCounter,
            recordingFPS: recordingFPS,
            streamingFPS: streamingFPS
        ) else {
            return
        }

        // 백그라운드에서 이미지 처리
        processingQueue.async { [weak self] in
            autoreleasepool {
                guard let self = self else { return }

                // JPEG 데이터 생성
                if let jpegData = self.imageProcessor.jpegDataFromSampleBuffer(
                    sampleBuffer,
                    targetSize: self.streamingResolution,
                    quality: self.jpegQuality
                ) {
                    // WebSocket으로 전송
                    self.sendFrame(jpegData)
                }
            }
        }
    }

    // MARK: - Network Transmission

    private func sendFrame(_ jpegData: Data) {
        // 메인 스레드가 아닌 네트워크 큐에서 전송
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.webSocketManager.sendBinaryData(jpegData)
        }
    }

    // MARK: - Statistics

    func getStreamingStats() -> (framesSent: Int, fps: Int32) {
        return (frameCounter, streamingFPS)
    }
}

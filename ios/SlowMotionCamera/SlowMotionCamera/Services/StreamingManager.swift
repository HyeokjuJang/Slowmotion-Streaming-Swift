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
    private var lastProcessedFrame: Int = 0
    private var isProcessing = false  // 처리 중 플래그
    private let processingQueue = DispatchQueue(
        label: Constants.Performance.processingQueueLabel,
        qos: Constants.Performance.processingQueueQoS
    )

    // 성능 모니터링
    private var streamedFrameCount: Int = 0
    private var lastLogTime: Date = Date()

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
        lastProcessedFrame = 0
        streamedFrameCount = 0
        isProcessing = false
        lastLogTime = Date()
    }

    // MARK: - Frame Processing

    /// 프레임 처리 및 스트리밍 (최적화 버전)
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

        // 이전 프레임이 아직 처리 중이면 스킵 (병목 방지)
        guard !isProcessing else {
            return
        }

        // 백그라운드에서 이미지 처리
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let resolution = streamingResolution
        let quality = jpegQuality

        isProcessing = true

        processingQueue.async { [weak self] in
            autoreleasepool {
                guard let self = self else { return }

                let startTime = CFAbsoluteTimeGetCurrent()

                // JPEG 데이터 생성
                if let jpegData = self.imageProcessor.jpegDataFromPixelBuffer(
                    pixelBuffer,
                    targetSize: resolution,
                    quality: quality
                ) {
                    // 직접 전송 (추가 큐 없이)
                    self.webSocketManager.sendBinaryData(jpegData)

                    self.streamedFrameCount += 1

                    let processingTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

                    // 성능 로그 (5초마다)
                    let now = Date()
                    if now.timeIntervalSince(self.lastLogTime) >= 5.0 {
                        let elapsed = now.timeIntervalSince(self.lastLogTime)
                        let actualFPS = Double(self.streamedFrameCount) / elapsed
                        print("📊 Streaming: \(String(format: "%.1f", actualFPS))fps (target: \(self.streamingFPS)fps) | Proc: \(String(format: "%.1f", processingTime))ms | Size: \(jpegData.count / 1024)KB")
                        self.streamedFrameCount = 0
                        self.lastLogTime = now
                    }
                }

                self.isProcessing = false
            }
        }
    }


    // MARK: - Statistics

    func getStreamingStats() -> (framesSent: Int, fps: Int32) {
        return (frameCounter, streamingFPS)
    }
}

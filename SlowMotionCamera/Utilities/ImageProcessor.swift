//
//  ImageProcessor.swift
//  SlowMotionCamera
//
//  이미지 리사이징, JPEG 압축 등의 처리
//

import Foundation
import CoreImage
import CoreVideo
import UIKit
import Accelerate

class ImageProcessor {

    // MARK: - Singleton
    static let shared = ImageProcessor()

    private let context: CIContext

    private init() {
        // Metal 지원 CIContext 생성 (GPU 가속)
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device)
        } else {
            context = CIContext()
        }
    }

    // MARK: - Image Conversion

    /// CMSampleBuffer를 UIImage로 변환
    func imageFromSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    /// CMSampleBuffer를 JPEG Data로 변환 (리사이징 + 압축)
    func jpegDataFromSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        targetSize: CGSize,
        quality: CGFloat = 0.7
    ) -> Data? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }

        // CIImage 생성
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // 리사이징
        let resizedImage = resize(ciImage: ciImage, to: targetSize)

        // CGImage로 변환
        guard let cgImage = context.createCGImage(resizedImage, from: resizedImage.extent) else {
            return nil
        }

        // UIImage로 변환
        let uiImage = UIImage(cgImage: cgImage)

        // JPEG 압축
        return uiImage.jpegData(compressionQuality: quality)
    }

    /// CIImage 리사이징
    private func resize(ciImage: CIImage, to targetSize: CGSize) -> CIImage {
        let sourceSize = ciImage.extent.size

        let scaleX = targetSize.width / sourceSize.width
        let scaleY = targetSize.height / sourceSize.height
        let scale = min(scaleX, scaleY)

        let transform = CGAffineTransform(scaleX: scale, y: scale)
        return ciImage.transformed(by: transform)
    }

    // MARK: - Pixel Buffer Processing

    /// CVPixelBuffer를 JPEG Data로 변환 (더 빠른 버전)
    func jpegDataFromPixelBuffer(
        _ pixelBuffer: CVPixelBuffer,
        targetSize: CGSize,
        quality: CGFloat = 0.7
    ) -> Data? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let resizedImage = resize(ciImage: ciImage, to: targetSize)

        guard let cgImage = context.createCGImage(resizedImage, from: resizedImage.extent) else {
            return nil
        }

        let uiImage = UIImage(cgImage: cgImage)
        return uiImage.jpegData(compressionQuality: quality)
    }

    // MARK: - Frame Downsampling

    /// 프레임 다운샘플링 결정 (fps 기반)
    /// - Parameters:
    ///   - currentFrame: 현재 프레임 번호
    ///   - recordingFPS: 녹화 fps
    ///   - streamingFPS: 스트리밍 fps
    /// - Returns: 이 프레임을 스트리밍해야 하는지 여부
    func shouldStreamFrame(currentFrame: Int, recordingFPS: Int32, streamingFPS: Int32) -> Bool {
        // 녹화 fps가 스트리밍 fps의 배수인 경우
        let ratio = Int(recordingFPS) / Int(streamingFPS)
        return currentFrame % ratio == 0
    }

    // MARK: - Memory Optimization

    /// 메모리 효율적인 이미지 처리 (autoreleasepool 사용)
    func processFrameEfficiently(
        _ sampleBuffer: CMSampleBuffer,
        targetSize: CGSize,
        quality: CGFloat,
        completion: @escaping (Data?) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            autoreleasepool {
                let jpegData = self.jpegDataFromSampleBuffer(
                    sampleBuffer,
                    targetSize: targetSize,
                    quality: quality
                )
                completion(jpegData)
            }
        }
    }
}

// MARK: - CGSize Extension
extension CGSize {
    var aspectRatio: CGFloat {
        return height > 0 ? width / height : 1.0
    }

    func scaled(by factor: CGFloat) -> CGSize {
        return CGSize(width: width * factor, height: height * factor)
    }

    func fitted(to targetSize: CGSize) -> CGSize {
        let scaleX = targetSize.width / width
        let scaleY = targetSize.height / height
        let scale = min(scaleX, scaleY)
        return scaled(by: scale)
    }
}

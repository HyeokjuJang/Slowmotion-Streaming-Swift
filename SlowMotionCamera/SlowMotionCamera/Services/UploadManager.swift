//
//  UploadManager.swift
//  SlowMotionCamera
//
//  비디오 파일 업로드 관리
//

import Foundation

class UploadManager: NSObject {

    // MARK: - Properties

    private var uploadSession: URLSession!
    private var currentUploadTask: URLSessionUploadTask?
    private var uploadProgressHandler: ((Double) -> Void)?
    private var uploadCompletionHandler: ((Bool, Error?) -> Void)?

    private let maxRetries = Constants.Network.uploadMaxRetries
    private var currentRetryCount = 0

    // MARK: - Initialization

    override init() {
        super.init()

        // 백그라운드 업로드를 위한 세션 설정
        let config = URLSessionConfiguration.background(
            withIdentifier: "com.slowmotioncamera.upload"
        )
        config.timeoutIntervalForRequest = Constants.Network.uploadTimeout
        config.timeoutIntervalForResource = Constants.Network.uploadTimeout * 2
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true

        uploadSession = URLSession(
            configuration: config,
            delegate: self,
            delegateQueue: nil
        )
    }

    // MARK: - Upload Methods

    /// 비디오 파일 업로드
    /// - Parameters:
    ///   - fileURL: 업로드할 파일의 로컬 URL
    ///   - serverURL: 업로드 서버 URL
    ///   - progress: 진행률 콜백
    ///   - completion: 완료 콜백
    func uploadVideo(
        fileURL: URL,
        to serverURL: String,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        guard let url = URL(string: serverURL) else {
            completion(false, NSError(
                domain: "UploadManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"]
            ))
            return
        }

        uploadProgressHandler = progress
        uploadCompletionHandler = completion
        currentRetryCount = 0

        performUpload(fileURL: fileURL, serverURL: url)
    }

    /// 재시도 로직을 포함한 업로드
    func uploadWithRetry(
        fileURL: URL,
        to serverURL: String,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        uploadVideo(fileURL: fileURL, to: serverURL, progress: progress) { [weak self] success, error in
            guard let self = self else { return }

            if !success && self.currentRetryCount < self.maxRetries {
                self.currentRetryCount += 1
                print("🔄 Retrying upload (\(self.currentRetryCount)/\(self.maxRetries))...")

                // 지수 백오프로 재시도
                let delay = pow(2.0, Double(self.currentRetryCount))
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                    guard let url = URL(string: serverURL) else { return }
                    self.performUpload(fileURL: fileURL, serverURL: url)
                }
            } else {
                completion(success, error)
            }
        }
    }

    /// 실제 업로드 수행
    private func performUpload(fileURL: URL, serverURL: URL) {
        // Multipart/form-data 요청 생성
        var request = URLRequest(url: serverURL)
        request.httpMethod = "POST"

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // 임시 파일에 multipart 데이터 작성
        let tempUploadURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        do {
            try createMultipartBody(
                fileURL: fileURL,
                boundary: boundary,
                outputURL: tempUploadURL
            )

            // 업로드 태스크 생성
            currentUploadTask = uploadSession.uploadTask(with: request, fromFile: tempUploadURL)
            currentUploadTask?.resume()

            print("📤 Starting upload: \(fileURL.lastPathComponent)")
        } catch {
            print("❌ Failed to create upload request: \(error)")
            uploadCompletionHandler?(false, error)
        }
    }

    /// Multipart body 생성
    private func createMultipartBody(
        fileURL: URL,
        boundary: String,
        outputURL: URL
    ) throws {
        let fileData = try Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent

        var body = Data()

        // 파일 파트 추가
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"video\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: video/quicktime\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)

        // 종료 boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        // 파일에 저장
        try body.write(to: outputURL)
    }

    // MARK: - Cancellation

    func cancelUpload() {
        currentUploadTask?.cancel()
        currentUploadTask = nil
        print("⚠️ Upload cancelled")
    }
}

// MARK: - URLSessionDelegate

extension UploadManager: URLSessionTaskDelegate, URLSessionDataDelegate {

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)

        DispatchQueue.main.async {
            self.uploadProgressHandler?(progress)
        }

        print("📊 Upload progress: \(Int(progress * 100))%")
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error = error {
            print("❌ Upload failed: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.uploadCompletionHandler?(false, error)
            }
        } else {
            print("✅ Upload completed successfully")
            DispatchQueue.main.async {
                self.uploadCompletionHandler?(true, nil)
            }
        }

        currentUploadTask = nil
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        // 서버 응답 처리
        if let response = String(data: data, encoding: .utf8) {
            print("📥 Server response: \(response)")
        }
    }
}

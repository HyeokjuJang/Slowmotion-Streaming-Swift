//
//  WebRTCCameraView.swift
//  SlowMotionCamera
//
//  WebRTC 기반 카메라 뷰
//

import SwiftUI
import AVFoundation

struct WebRTCCameraView: View {

    @ObservedObject var controller: WebRTCViewController
    @State private var showSettings = false

    var body: some View {
        ZStack {
            // 카메라 프리뷰
            WebRTCPreviewView(previewLayer: controller.previewLayer)
                .ignoresSafeArea()

            // UI 오버레이
            VStack {
                // 상단 상태바
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(controller.connectionStatus)
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(8)

                        Text(controller.recordingStatus)
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(controller.isRecording ? Color.red.opacity(0.8) : Color.black.opacity(0.7))
                            .cornerRadius(8)
                    }

                    Spacer()

                    Button(action: {
                        showSettings = true
                    }) {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.black.opacity(0.7))
                            .clipShape(Circle())
                    }
                }
                .padding()

                Spacer()

                // 하단 컨트롤
                HStack(spacing: 40) {
                    // 연결/해제 버튼
                    Button(action: {
                        if controller.connectionStatus.contains("연결됨") {
                            controller.disconnect()
                        } else {
                            controller.connect()
                        }
                    }) {
                        VStack {
                            Image(systemName: controller.connectionStatus.contains("연결됨") ? "wifi" : "wifi.slash")
                                .font(.system(size: 30))
                            Text(controller.connectionStatus.contains("연결됨") ? "연결 해제" : "서버 연결")
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                        .frame(width: 80, height: 80)
                        .background(controller.connectionStatus.contains("연결됨") ? Color.green.opacity(0.8) : Color.gray.opacity(0.8))
                        .cornerRadius(16)
                    }

                    // 녹화 버튼 (자동 제어 - 서버에서 명령)
                    VStack {
                        Circle()
                            .fill(controller.isRecording ? Color.red : Color.white)
                            .frame(width: 70, height: 70)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 4)
                            )

                        Text(controller.isRecording ? "녹화중" : "대기중")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $showSettings) {
            // 설정 화면
            SettingsView(
                settings: controller.settings,
                isPresented: $showSettings,
                onConnect: {
                    showSettings = false
                }
            )
        }
        .onAppear {
            // 서버 연결 (카메라 설정 포함)
            controller.connect()
        }
        .onDisappear {
            controller.stopSession()
            controller.disconnect()
        }
    }
}

// MARK: - WebRTC Preview View (UIKit Wrapper)

struct WebRTCPreviewView: UIViewRepresentable {

    let previewLayer: AVCaptureVideoPreviewLayer?

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black

        if let previewLayer = previewLayer {
            previewLayer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(previewLayer)
            print("✅ Preview layer added to view in makeUIView")
        } else {
            print("⚠️ No preview layer available in makeUIView")
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let previewLayer = previewLayer else {
            print("⚠️ No preview layer in updateUIView")
            return
        }

        // frame 업데이트
        DispatchQueue.main.async {
            if previewLayer.frame != uiView.bounds {
                previewLayer.frame = uiView.bounds
                print("📐 Updated preview layer frame: \(uiView.bounds)")
            }
        }
    }
}

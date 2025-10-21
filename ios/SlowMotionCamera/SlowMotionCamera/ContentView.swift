//
//  ContentView.swift
//  SlowMotionCamera
//
//  앱의 루트 뷰
//

import SwiftUI
import AVFoundation

struct ContentView: View {

    @StateObject private var settings = CameraSettings()
    @StateObject private var state = RecordingStateManager()
    @State private var showSettings = false
    @State private var cameraPermissionGranted = false

    var body: some View {
        Group {
            if !cameraPermissionGranted {
                // 권한 요청 화면
                PermissionView(permissionGranted: $cameraPermissionGranted)
            } else if showSettings || settings.serverURL.isEmpty {
                // 설정 화면
                SettingsView(
                    settings: settings,
                    isPresented: $showSettings,
                    onConnect: {
                        showSettings = false
                    }
                )
            } else {
                // 메인 카메라 화면
                CameraView(controller: CameraViewController(settings: settings, state: state))
            }
        }
        .onAppear {
            checkCameraPermission()
        }
    }

    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraPermissionGranted = true

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    cameraPermissionGranted = granted
                }
            }

        default:
            cameraPermissionGranted = false
        }
    }
}

// MARK: - Permission View

struct PermissionView: View {

    @Binding var permissionGranted: Bool

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "video.fill")
                .font(.system(size: 72))
                .foregroundColor(.blue)

            Text("카메라 권한 필요")
                .font(.title)
                .fontWeight(.bold)

            Text("슬로우모션 비디오를 녹화하기 위해\n카메라 접근 권한이 필요합니다.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Button(action: {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }) {
                Text("설정으로 이동")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .cornerRadius(10)
            }

            Button(action: {
                checkPermission()
            }) {
                Text("다시 확인")
                    .foregroundColor(.blue)
            }
        }
        .padding()
    }

    private func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionGranted = true

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    permissionGranted = granted
                }
            }

        default:
            break
        }
    }
}

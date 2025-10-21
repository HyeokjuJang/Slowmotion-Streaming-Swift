# iOS 슬로우모션 원격 제어 카메라 앱

원격 서버에서 제어 가능한 iOS 슬로우모션 녹화 앱입니다. 고fps 비디오를 녹화하면서 동시에 낮은 해상도/fps로 실시간 스트리밍하여 원격 모니터링이 가능합니다.

## 주요 기능

- **고fps 슬로우모션 녹화**: 60/120/240fps @ 720p/1080p/4K
- **실시간 스트리밍**: 낮은 fps/해상도로 다운샘플링하여 WebSocket으로 스트리밍
- **원격 제어**: WebSocket을 통해 start/stop 명령 수신
- **자동 업로드**: 녹화 완료 후 서버로 자동 업로드 (재시도 지원)
- **상태 보고**: 실시간 상태 업데이트 (waiting, recording, uploading)

## 프로젝트 구조

```
record-streaming/
├── SlowMotionCamera/           # iOS 앱
│   ├── App/                    # 앱 진입점
│   │   ├── SlowMotionCameraApp.swift
│   │   └── ContentView.swift
│   ├── Models/                 # 데이터 모델
│   │   ├── CameraSettings.swift
│   │   └── RecordingState.swift
│   ├── Views/                  # UI 뷰
│   │   ├── SettingsView.swift
│   │   ├── CameraView.swift
│   │   └── CameraPreviewView.swift
│   ├── Services/               # 핵심 서비스
│   │   ├── CameraManager.swift
│   │   ├── WebSocketManager.swift
│   │   ├── StreamingManager.swift
│   │   └── UploadManager.swift
│   └── Utilities/              # 유틸리티
│       ├── Constants.swift
│       └── ImageProcessor.swift
├── server/                     # Node.js 서버
│   ├── server.js
│   ├── package.json
│   └── public/
│       └── viewer.html
├── Package.swift               # Swift Package Manager
└── Info.plist                  # iOS 앱 설정
```

## 시작하기

### 1. 서버 설정

서버는 Node.js로 작성되었으며, WebSocket과 HTTP를 모두 지원합니다.

```bash
cd server
npm install
npm start
```

서버가 시작되면:
- HTTP 서버: `http://localhost:3000`
- WebSocket 서버: `ws://localhost:8080`
- 웹 뷰어: `http://localhost:3000/viewer.html`

### 2. iOS 앱 빌드

Xcode에서 프로젝트를 열고 빌드합니다.

#### Xcode 프로젝트 생성

```bash
# Xcode에서 새 iOS App 프로젝트 생성
# - Product Name: SlowMotionCamera
# - Interface: SwiftUI
# - Life Cycle: SwiftUI App
# - Language: Swift
# - Minimum Deployment: iOS 15.0
```

#### Swift Package 의존성 추가

Xcode에서:
1. File → Add Package Dependencies
2. URL 입력: `https://github.com/daltoniam/Starscream.git`
3. Version: 4.0.0 이상

#### 파일 구조 복사

생성된 Xcode 프로젝트에 `SlowMotionCamera/` 디렉토리의 파일들을 복사합니다.

#### Info.plist 설정

프로젝트의 Info.plist에 다음 권한 추가:

```xml
<key>NSCameraUsageDescription</key>
<string>슬로우모션 비디오를 녹화하기 위해 카메라 접근이 필요합니다.</string>

<key>NSMicrophoneUsageDescription</key>
<string>오디오를 녹음하기 위해 마이크 접근이 필요합니다.</string>

<key>NSLocalNetworkUsageDescription</key>
<string>로컬 서버와 통신하기 위해 네트워크 접근이 필요합니다.</string>

<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

### 3. 앱 사용법

1. **설정**
   - 서버 URL 입력 (예: `ws://192.168.1.100:8080/camera`)
   - 녹화 설정 선택 (FPS, 해상도)
   - 스트리밍 설정 선택 (FPS, 해상도, JPEG 품질)

2. **연결**
   - "연결 및 대기 시작" 버튼 클릭
   - WebSocket 연결 확인
   - 카메라 프리뷰 시작

3. **녹화 제어**
   - 웹 뷰어 (`http://서버주소:3000/viewer.html`) 접속
   - "녹화 시작" 버튼 클릭
   - iOS 앱에서 녹화 시작, 실시간 스트리밍
   - "녹화 종료" 버튼 클릭
   - 자동으로 서버에 업로드

## API 레퍼런스

### WebSocket 프로토콜

#### 카메라 → 서버 (상태 메시지)

```json
{
  "type": "status",
  "status": "waiting|recording|uploading",
  "timestamp": 1234567890.123
}
```

#### 서버 → 카메라 (제어 명령)

```json
{
  "command": "start"
}
```

```json
{
  "command": "stop"
}
```

#### 카메라 → 서버 (비디오 프레임)

- Binary data (JPEG 형식)
- 약 20-50KB per frame

### HTTP API

#### 녹화 제어

```bash
# 녹화 시작
POST http://서버주소:3000/control/start

# 녹화 종료
POST http://서버주소:3000/control/stop
```

#### 비디오 업로드

```bash
POST http://서버주소:3000/upload
Content-Type: multipart/form-data

# Form field: video (file)
```

#### 서버 상태

```bash
GET http://서버주소:3000/status

# Response:
{
  "cameras": 1,
  "viewers": 2,
  "timestamp": 1234567890123
}
```

#### 업로드된 비디오 목록

```bash
GET http://서버주소:3000/videos

# Response:
{
  "success": true,
  "videos": [
    {
      "filename": "video_1234567890.mov",
      "size": 12345678,
      "created": "2025-10-21T10:00:00.000Z"
    }
  ]
}
```

## 설정 옵션

### 녹화 설정

| 옵션 | 기본값 | 가능한 값 |
|------|--------|-----------|
| FPS | 120fps | 60, 120, 240 |
| 해상도 | 1080p | 720p, 1080p, 4K |

### 스트리밍 설정

| 옵션 | 기본값 | 가능한 값 |
|------|--------|-----------|
| FPS | 15fps | 10, 15, 30 |
| 해상도 | 720p | 480p, 720p, 1080p |
| JPEG 품질 | 70% | 50-100% |

### 네트워크 설정

| 옵션 | 기본값 | 설명 |
|------|--------|------|
| WebSocket 재연결 간격 | 5초 | 연결 끊김 시 재연결 시도 간격 |
| 최대 재연결 횟수 | 5회 | 재연결 최대 시도 횟수 |
| 업로드 재시도 횟수 | 3회 | 업로드 실패 시 재시도 횟수 |

## 아키텍처

### iOS 앱

- **SwiftUI**: 선언적 UI
- **AVFoundation**: 고fps 카메라 녹화
- **Starscream**: WebSocket 통신
- **URLSession**: 백그라운드 파일 업로드

### 서버

- **Express.js**: HTTP 서버
- **ws**: WebSocket 서버
- **Multer**: 파일 업로드 처리

### 통신 흐름

```
┌─────────────┐         WebSocket          ┌─────────────┐
│             │◄──────────────────────────►│             │
│  iOS 앱     │  제어 명령 (JSON)           │   서버      │
│             │  상태 메시지 (JSON)         │             │
│  (카메라)   │  비디오 프레임 (Binary)     │             │
└─────────────┘                             └─────────────┘
       │                                            ▲
       │ HTTP POST                                  │
       │ multipart/form-data                        │
       └────────────────────────────────────────────┘
                    비디오 파일 업로드

┌─────────────┐         WebSocket          ┌─────────────┐
│             │◄──────────────────────────►│             │
│  웹 뷰어    │  비디오 프레임 수신         │   서버      │
│             │  제어 명령 전송             │             │
└─────────────┘                             └─────────────┘
```

## 성능 최적화

### 메모리 관리

- CVPixelBuffer 재사용
- `autoreleasepool` 사용 (고fps 처리)
- 메모리 경고 시 캐시 정리

### 멀티스레딩

- 카메라 캡처: 고우선순위 큐
- 이미지 처리: 백그라운드 큐
- 네트워크 전송: 백그라운드 큐
- UI 업데이트: 메인 큐

### 하드웨어 가속

- Metal을 통한 CIContext (GPU 가속)
- Core Image를 통한 이미지 처리
- VideoToolbox 고려 (H.264 인코딩)

## 문제 해결

### 카메라 권한 오류

앱 설정에서 카메라 권한을 확인하고 허용하세요.

### WebSocket 연결 실패

- 서버가 실행 중인지 확인
- 방화벽 설정 확인
- 올바른 IP 주소와 포트 사용

### 업로드 실패

- 서버의 디스크 공간 확인
- 네트워크 연결 상태 확인
- 서버 로그 확인

### 낮은 FPS 또는 프레임 드롭

- 스트리밍 해상도 낮추기
- JPEG 품질 낮추기
- 스트리밍 FPS 낮추기

## 라이선스

MIT License

## 기여

이슈와 PR은 언제나 환영합니다!

## 참고 문서

- [REQUIREMENTS.md](REQUIREMENTS.md) - 상세 요구사항
- [AVFoundation 공식 문서](https://developer.apple.com/av-foundation/)
- [Starscream GitHub](https://github.com/daltoniam/Starscream)

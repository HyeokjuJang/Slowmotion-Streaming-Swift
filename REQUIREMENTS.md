# iOS 슬로우모션 원격 제어 카메라 앱 개발 요구사항

## 📋 프로젝트 개요

원격 서버에서 제어 가능한 iOS 슬로우모션 녹화 앱입니다. 고fps 비디오를 녹화하면서 동시에 낮은 해상도/fps로 실시간 스트리밍하여 원격 모니터링이 가능합니다.

---

## 🎯 핵심 기능

### 1. 슬로우모션 녹화

-   **녹화 fps**: 120fps (설정 가능)
-   **녹화 해상도**: 1080p (1920x1080, 설정 가능)
-   **포맷**: H.264 비디오, .mov 파일
-   **저장 위치**: 앱 Documents 디렉토리

### 2. 실시간 스트리밍

-   **스트리밍 fps**: 15fps (설정 가능, 녹화 fps에서 다운샘플링)
-   **스트리밍 해상도**: 720p (1280x720, 설정 가능)
-   **압축**: JPEG 70% 품질
-   **프로토콜**: WebSocket (바이너리 데이터)
-   **지연 시간**: 500ms-1s

### 3. 원격 제어

-   **제어 프로토콜**: WebSocket (JSON 메시지)
-   **명령어**:
    -   `start`: 녹화 시작
    -   `stop`: 녹화 종료
-   **상태 보고**:
    -   `waiting`: 대기 중
    -   `recording`: 녹화 중

### 4. 자동 업로드

-   녹화 완료 후 자동으로 서버에 비디오 파일 업로드
-   HTTP POST multipart/form-data
-   백그라운드 업로드 지원 (URLSession background configuration)
-   업로드 실패 시 재시도 (최대 3회)

---

## 🖥️ UI/UX 요구사항

### 설정 화면

**입력 필드:**

-   서버 주소 (WebSocket URL)
    -   예: `ws://192.168.1.100:8080/camera`
    -   Placeholder: "ws://서버주소:포트/camera"
-   녹화 설정
    -   FPS 선택: 60fps, 120fps, 240fps (Picker/Segmented Control)
    -   해상도 선택: 720p, 1080p, 4K (지원 여부 체크)
-   스트리밍 설정
    -   FPS 선택: 10fps, 15fps, 30fps
    -   해상도 선택: 480p, 720p, 1080p

**UI 구성:**

```
┌─────────────────────────────┐
│ 설정                         │
├─────────────────────────────┤
│ 서버 주소                    │
│ [ws://192.168.1.100:8080]   │
│                              │
│ 녹화 설정                    │
│ FPS:  [60] [120] [240]      │
│ 해상도: [720p] [1080p] [4K] │
│                              │
│ 스트리밍 설정                │
│ FPS:  [10] [15] [30]        │
│ 해상도: [480p] [720p]       │
│                              │
│      [연결 및 대기 시작]     │
└─────────────────────────────┘
```

### 메인 화면 (녹화/대기)

**UI 구성:**

```
┌─────────────────────────────┐
│ ← 설정                      │
├─────────────────────────────┤
│                              │
│   [카메라 프리뷰 영역]       │
│                              │
│                              │
├─────────────────────────────┤
│ 상태: 🟡 서버 대기 중        │
│       🔴 녹화 중             │
│       🟢 업로드 중           │
│                              │
│ 연결: ws://192.168.1.100... │
│ 녹화: 120fps @ 1080p        │
│ 스트리밍: 15fps @ 720p      │
└─────────────────────────────┘
```

**상태 표시:**

-   🟡 대기 중 (서버 연결됨, 명령 대기)
-   🔴 녹화 중 (실시간 프레임 카운트 표시)
-   🟢 업로드 중 (진행률 표시)
-   ⚠️ 오류 (연결 끊김, 녹화 실패 등)

---

## 🏗️ 기술 스택

### iOS (Swift)

-   **언어**: Swift 5.9+
-   **최소 iOS**: iOS 15.0+
-   **UI 프레임워크**: SwiftUI
-   **카메라**: AVFoundation
    -   `AVCaptureSession`
    -   `AVCaptureDevice`
    -   `AVCaptureVideoDataOutput`
    -   `AVAssetWriter`
-   **네트워킹**:
    -   `Starscream` (WebSocket 라이브러리)
    -   `URLSession` (파일 업로드)

### 서버 (Node.js)

-   **언어**: JavaScript (Node.js)
-   **WebSocket**: `ws` 라이브러리
-   **HTTP 서버**: Express.js
-   **파일 업로드**: Multer

---

## 📡 통신 프로토콜

### WebSocket 연결

**카메라 앱 → 서버**

-   URL: `ws://서버주소:8080/camera`
-   연결 시 자동으로 `waiting` 상태 전송

### 제어 메시지 (JSON, 텍스트)

**서버 → 카메라 (제어 명령)**

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

**카메라 → 서버 (상태 보고)**

```json
{
    "type": "status",
    "status": "waiting|recording|uploading",
    "timestamp": 1234567890.123
}
```

### 비디오 스트리밍 (바이너리)

**카메라 → 서버**

-   다운샘플링된 JPEG 프레임을 바이너리로 전송
-   각 프레임은 독립적인 JPEG 이미지
-   메시지 크기: 약 20-50KB per frame

---

## 🔄 동작 시퀀스

### 앱 시작 플로우

```
1. 사용자가 설정 입력
2. "연결 및 대기 시작" 버튼 클릭
3. WebSocket 연결 시도
4. 연결 성공 → 카메라 프리뷰 시작
5. 서버에 "waiting" 상태 전송
6. 명령 대기...
```

### 녹화 플로우

```
1. 서버에서 "start" 명령 수신
2. AVAssetWriter 초기화 및 녹화 시작
3. 서버에 "recording" 상태 전송
4. 매 프레임마다:
   - 전체 프레임 → 로컬 파일에 저장 (120fps)
   - 다운샘플링 프레임 → WebSocket 스트리밍 (15fps)
5. 서버에서 "stop" 명령 수신
6. AVAssetWriter 종료 및 파일 저장
7. 서버에 "uploading" 상태 전송
8. HTTP POST로 비디오 파일 업로드
9. 업로드 완료 → 로컬 파일 삭제 (옵션)
10. 서버에 "waiting" 상태 전송
11. 다음 명령 대기...
```

---

## 📂 파일 구조

### iOS 앱

```
SlowMotionCamera/
├── App/
│   ├── SlowMotionCameraApp.swift
│   └── ContentView.swift
├── Views/
│   ├── SettingsView.swift          # 설정 화면
│   ├── CameraView.swift            # 메인 녹화 화면
│   └── CameraPreviewView.swift     # 카메라 프리뷰 UIViewRepresentable
├── Models/
│   ├── CameraSettings.swift        # 설정 데이터 모델
│   └── RecordingState.swift        # 앱 상태 모델
├── Services/
│   ├── CameraManager.swift         # AVFoundation 카메라 관리
│   ├── WebSocketManager.swift      # WebSocket 연결 및 제어
│   ├── StreamingManager.swift      # 비디오 스트리밍
│   └── UploadManager.swift         # 파일 업로드
└── Utilities/
    ├── ImageProcessor.swift        # 이미지 리사이징, JPEG 압축
    └── Constants.swift             # 상수 정의
```

### 서버

```
server/
├── server.js                       # WebSocket 서버
├── routes/
│   └── control.js                  # HTTP 제어 API
├── uploads/                        # 업로드된 비디오 저장
└── public/
    └── viewer.html                 # 웹 모니터링 페이지
```

---

## 🔧 주요 구현 사항

### 1. CameraManager.swift

**책임:**

-   AVCaptureSession 설정 및 관리
-   고fps 포맷 선택 및 설정
-   AVAssetWriter로 비디오 녹화
-   프레임 캡처 및 델리게이트 처리

**주요 메서드:**

```swift
func setupCamera(fps: Int, resolution: CGSize)
func startRecording()
func stopRecording() -> URL  // 저장된 파일 URL 반환
func captureOutput(_:didOutput:from:)  // 프레임 콜백
```

### 2. WebSocketManager.swift

**책임:**

-   WebSocket 연결 관리
-   제어 명령 수신 및 파싱
-   상태 메시지 전송

**주요 메서드:**

```swift
func connect(to url: String)
func disconnect()
func sendStatus(_ status: String)
func handleCommand(_ command: String)
```

### 3. StreamingManager.swift

**책임:**

-   프레임 다운샘플링 (fps 감소)
-   이미지 리사이징 (해상도 감소)
-   JPEG 압축
-   WebSocket으로 바이너리 전송

**주요 메서드:**

```swift
func processFrame(_ sampleBuffer: CMSampleBuffer,
                 recordingFPS: Int,
                 streamingFPS: Int,
                 targetResolution: CGSize)
func sendFrameToServer(_ jpegData: Data)
```

### 4. UploadManager.swift

**책임:**

-   HTTP multipart/form-data 업로드
-   백그라운드 업로드 설정
-   재시도 로직
-   진행률 추적

**주요 메서드:**

```swift
func uploadVideo(fileURL: URL, to serverURL: String, completion: @escaping (Bool) -> Void)
func uploadWithRetry(fileURL: URL, maxRetries: Int)
```

---

## 🎨 성능 최적화

### 메모리 관리

-   CVPixelBuffer 재사용 풀 사용
-   autoreleasepool 활용 (고fps 처리 시)
-   메모리 경고 시 캐시 정리

### 멀티스레딩

-   카메라 캡처: 별도 큐 (고우선순위)
-   이미지 처리: 백그라운드 큐
-   UI 업데이트: 메인 큐
-   네트워크 전송: 백그라운드 큐

```swift
let captureQueue = DispatchQueue(label: "camera.capture",
                                qos: .userInitiated)
let processingQueue = DispatchQueue(label: "image.processing",
                                   qos: .userInitiated)
let networkQueue = DispatchQueue(label: "network",
                                qos: .utility)
```

### 하드웨어 가속

-   VideoToolbox 사용 고려 (H.264 인코딩)
-   Metal 또는 Core Image로 이미지 처리

---

## 📊 설정 가능한 옵션

### 녹화 설정

| 옵션   | 기본값 | 가능한 값       |
| ------ | ------ | --------------- |
| FPS    | 120fps | 60, 120, 240    |
| 해상도 | 1080p  | 720p, 1080p, 4K |

### 스트리밍 설정

| 옵션      | 기본값 | 가능한 값         |
| --------- | ------ | ----------------- |
| FPS       | 15fps  | 10, 15, 30        |
| 해상도    | 720p   | 480p, 720p, 1080p |
| JPEG 품질 | 70%    | 50-100%           |

### 서버 설정

| 옵션          | 기본값 | 설명                    |
| ------------- | ------ | ----------------------- |
| WebSocket URL | -      | ws://host:port/camera   |
| 업로드 URL    | -      | http://host:port/upload |
| 재시도 횟수   | 3      | 업로드 실패 시 재시도   |

---

## 🛡️ 에러 처리

### 카메라 권한

```swift
// 카메라 권한 요청 및 확인
AVCaptureDevice.requestAccess(for: .video) { granted in
    if !granted {
        // 설정 앱으로 이동 유도
    }
}
```

### 네트워크 오류

-   WebSocket 연결 실패 → 재연결 시도 (5초 간격, 최대 5회)
-   업로드 실패 → 재시도 (지수 백오프)
-   타임아웃 설정: WebSocket 30초, HTTP 업로드 300초

### 디스크 용량

-   녹화 시작 전 여유 공간 확인 (최소 1GB)
-   공간 부족 시 경고 및 녹화 중단

### 앱 라이프사이클

-   백그라운드 진입 시 녹화 일시정지/계속 처리
-   앱 종료 시 녹화 중이면 저장 후 종료

---

## 🧪 테스트 시나리오

### 기본 동작 테스트

1. ✅ 설정 입력 후 서버 연결
2. ✅ 서버에서 start 명령 → 녹화 시작
3. ✅ 녹화 중 스트리밍 확인 (웹 뷰어)
4. ✅ 서버에서 stop 명령 → 녹화 종료
5. ✅ 자동 업로드 완료
6. ✅ 다시 대기 상태로 복귀

### 에지 케이스

-   [ ] 녹화 중 앱 백그라운드 진입
-   [ ] 녹화 중 WebSocket 연결 끊김
-   [ ] 업로드 중 네트워크 끊김
-   [ ] 디스크 공간 부족
-   [ ] 지원하지 않는 fps/해상도 조합

### 성능 테스트

-   [ ] 10분 연속 녹화 (메모리 누수 확인)
-   [ ] 여러 번 반복 녹화 (안정성)
-   [ ] 동시 녹화 + 스트리밍 CPU/메모리 사용률

---

## 📝 Info.plist 설정

```xml
<!-- 카메라 권한 -->
<key>NSCameraUsageDescription</key>
<string>슬로우모션 비디오를 녹화하기 위해 카메라 접근이 필요합니다.</string>

<!-- 마이크 권한 (오디오 녹음 시) -->
<key>NSMicrophoneUsageDescription</key>
<string>오디오를 녹음하기 위해 마이크 접근이 필요합니다.</string>

<!-- 로컬 네트워크 접근 -->
<key>NSLocalNetworkUsageDescription</key>
<string>로컬 서버와 통신하기 위해 네트워크 접근이 필요합니다.</string>

<key>NSBonjourServices</key>
<array>
    <string>_http._tcp</string>
</array>

<!-- 백그라운드 모드 -->
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>  <!-- 백그라운드 녹화 -->
</array>
```

---

## 📦 Dependencies (Package.swift 또는 Podfile)

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/daltoniam/Starscream.git", from: "4.0.0")
]
```

또는

```ruby
# Podfile
pod 'Starscream', '~> 4.0'
```

---

## 🚀 개발 우선순위

### Phase 1: MVP (1주)

1. ✅ 기본 카메라 녹화 (120fps @ 1080p)
2. ✅ WebSocket 연결 및 제어 명령 처리
3. ✅ 간단한 스트리밍 (JPEG over WebSocket)
4. ✅ 기본 UI (설정 + 메인 화면)

### Phase 2: 기능 완성 (1주)

1. ✅ 자동 업로드
2. ✅ 설정 화면 완성 (다양한 fps/해상도)
3. ✅ 에러 처리 및 재연결 로직
4. ✅ 상태 표시 개선

### Phase 3: 최적화 (3-5일)

1. ✅ 성능 최적화 (메모리, CPU)
2. ✅ 배터리 최적화
3. ✅ UI/UX 개선
4. ✅ 테스트 및 버그 수정

---

## 🌐 서버 구현 (참고용)

### server.js (WebSocket + HTTP)

```javascript
const WebSocket = require('ws');
const express = require('express');
const multer = require('multer');
const path = require('path');

const app = express();
const wss = new WebSocket.Server({ port: 8080 });

// 파일 업로드 설정
const storage = multer.diskStorage({
    destination: './uploads/',
    filename: (req, file, cb) => {
        cb(null, `video_${Date.now()}.mov`);
    },
});
const upload = multer({ storage });

// WebSocket 연결 관리
let cameras = new Map();
let viewers = new Map();

wss.on('connection', (ws, req) => {
    const path = req.url;

    if (path.includes('/camera')) {
        handleCameraConnection(ws);
    } else if (path.includes('/viewer')) {
        handleViewerConnection(ws);
    }
});

function handleCameraConnection(ws) {
    const id = Date.now();
    cameras.set(id, ws);
    console.log(`카메라 연결: ${id}`);

    ws.on('message', (message) => {
        if (message instanceof Buffer) {
            // 비디오 프레임 → 모든 뷰어에게 전달
            viewers.forEach((viewer) => {
                if (viewer.readyState === WebSocket.OPEN) {
                    viewer.send(message);
                }
            });
        } else {
            // 상태 메시지
            const data = JSON.parse(message);
            console.log(`카메라 ${id} 상태:`, data.status);
        }
    });

    ws.on('close', () => {
        cameras.delete(id);
        console.log(`카메라 연결 종료: ${id}`);
    });
}

function handleViewerConnection(ws) {
    const id = Date.now();
    viewers.set(id, ws);
    console.log(`뷰어 연결: ${id}`);

    ws.on('close', () => {
        viewers.delete(id);
    });
}

// HTTP API (제어)
app.post('/control/start', (req, res) => {
    cameras.forEach((camera) => {
        if (camera.readyState === WebSocket.OPEN) {
            camera.send(JSON.stringify({ command: 'start' }));
        }
    });
    res.json({ success: true });
});

app.post('/control/stop', (req, res) => {
    cameras.forEach((camera) => {
        if (camera.readyState === WebSocket.OPEN) {
            camera.send(JSON.stringify({ command: 'stop' }));
        }
    });
    res.json({ success: true });
});

// 파일 업로드
app.post('/upload', upload.single('video'), (req, res) => {
    console.log('비디오 업로드:', req.file.filename);
    res.json({
        success: true,
        filename: req.file.filename,
    });
});

// 정적 파일 (뷰어 페이지)
app.use(express.static('public'));

app.listen(3000, () => {
    console.log('HTTP 서버: http://localhost:3000');
    console.log('WebSocket 서버: ws://localhost:8080');
});
```

---

## 📌 추가 고려사항

### 보안

-   WebSocket: WSS (TLS) 사용 권장
-   업로드: HTTPS 사용
-   인증: 토큰 기반 인증 추가 고려

### 확장성

-   여러 카메라 동시 지원
-   카메라 ID/이름 지정
-   뷰어별 카메라 선택 기능

### 미래 기능

-   오디오 녹음 지원
-   실시간 필터/이펙트
-   클라우드 스토리지 연동
-   녹화 파일 리스트 및 재생

---

## 💬 질문/이슈 사항

개발 중 질문이나 문제가 발생하면:

1. 기술적 제약사항 확인 (iOS 버전, 기기 지원)
2. 성능 트레이드오프 고려
3. 대안 솔루션 검토

---

**문서 버전**: 1.0  
**작성일**: 2025-10-21  
**개발 예상 기간**: 2-3주

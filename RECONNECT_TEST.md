# 재연결 테스트 가이드

## 수정된 재연결 순서 (올바른 방법)

```
1️⃣ Python: 기존 peer connection close
2️⃣ Python: 새로운 peer connection 생성
3️⃣ Python: 이벤트 핸들러 재등록
4️⃣ Python → Server: {"type": "reconnect_request"}
5️⃣ Server → iPhone: {"command": "reconnect"}
6️⃣ iPhone: close() + setupPeerConnection() + createOffer()
7️⃣ iPhone → Python: Offer 전송
8️⃣ Python: 준비된 새 connection으로 offer 처리
9️⃣ Python → iPhone: Answer 전송
🔟 WebRTC 연결 재수립 완료
```

## 왜 이 순서가 중요한가?

### ❌ 잘못된 순서 (이전)
```
Python이 reconnect 신호만 보냄
  ↓
iPhone이 close() → offer 전송
  ↓
Python의 old connection도 close됨 (iPhone close의 부작용)
  ↓
Python: "signaling state: closed" 에러
  ↓
실패!
```

### ✅ 올바른 순서 (현재)
```
Python이 먼저 clean up
  ↓
새로운 peer connection 준비
  ↓
그 다음 reconnect 신호
  ↓
iPhone의 offer를 깨끗한 상태에서 받음
  ↓
성공!
```

## 테스트

### 1. 서버 시작
```bash
cd server
npm start
```

### 2. iOS 앱 재빌드
```bash
# Xcode: Product → Clean Build Folder → Run
```

### 3. Python 실행
```bash
python3 rtmlib_webrtc_receiver_simple.py
```

### 4. 정상 동작 확인
```
15:20:00 [INFO] 📹 Frame 60 | FPS: 30.0
15:20:02 [INFO] 📹 Frame 120 | FPS: 30.0
15:20:04 [INFO] 📹 Frame 180 | FPS: 30.0
```

### 5. 강제 끊김 (WiFi 끄기)
```
iPhone에서:
Settings → WiFi → Off
(10초 대기)
WiFi → On
```

## 예상 로그

### Python 로그 (성공 시)
```
15:20:40 [INFO] 📹 Frame 900 | FPS: 30.0
(WiFi 끊김)
15:20:47 [ERROR] ❌ No frames for 5s! (failure #1)
15:20:50 [ERROR] ❌ No frames for 8s! (failure #2)
15:20:53 [ERROR] ❌ No frames for 11s! (failure #3)
15:20:53 [ERROR] 💀 Connection DEAD after 11s
15:20:53 [INFO] 🔄 Initiating reconnection...
15:20:53 [INFO] 1️⃣ Closing old peer connection...
15:20:53 [INFO] 2️⃣ Creating new peer connection...
15:20:53 [INFO] 3️⃣ Requesting new offer from camera...
15:20:53 [INFO] ⏳ Waiting 30s for reconnection...
(WiFi 복구)
15:20:55 [INFO] 📥 Received offer
15:20:55 [INFO] 📤 Sent answer
15:20:56 [INFO] 🧊 ICE: type=host, ip=192.168.1.100, port=54321
15:20:56 [INFO] 🔌 Connection state: connected
15:20:56 [INFO] 🧊 ICE state: connected
15:20:56 [INFO] ✅ WebRTC connection established!
15:20:56 [INFO] 🎬 Track received: video
15:21:00 [INFO] 📹 Frame 960 | FPS: 30.0
15:21:23 [INFO] ✅ Reconnection successful! Resuming monitoring...
```

### Server 로그
```
🔄 Reconnection requested from viewer: No frames for 11s
📤 Sending reconnect command to camera (ID: 1234567890)
📡 WebRTC signaling from camera: offer
📡 WebRTC signaling from viewer: answer
📡 WebRTC signaling from camera: ice
```

### iPhone 로그 (Xcode Console)
```
📥 Command received: reconnect
🔄 Reconnection requested - restarting WebRTC connection
🔄 Starting WebRTC reconnection...
🔄 Closing existing peer connection
✅ Peer connection created
📤 Sending offer...
✅ Offer created with bitrate limit and set as local description
🧊 ICE candidate generated
🧊 ICE connection state: 1 (checking)
🧊 ICE connection state: 2 (connected)
✅ Answer set as remote description
📹 WebRTC frames sent: 90 (skipped 270 frames)
```

## 트러블슈팅

### 문제 1: "signaling state: closed" 에러
```
15:20:53 [INFO] 📥 Received offer
15:20:53 [ERROR] Error handling message: Cannot handle offer in signaling state "closed"
```

**원인**: Python이 새 connection을 생성하기 전에 offer를 받음
**해결**: 코드 순서 확인 - close → 새 connection → reconnect 신호

### 문제 2: 30초 후에도 재연결 실패
```
15:21:23 [ERROR] ❌ Reconnection failed
```

**가능한 원인**:
1. iPhone 앱이 죽음 → Xcode에서 확인
2. WiFi가 완전히 끊김 → 네트워크 확인
3. Server가 죽음 → 서버 로그 확인

**해결**:
- iPhone 앱 재시작
- Python 스크립트 재시작
- 서버 재시작

### 문제 3: 무한 재연결 루프
```
15:20:53 [INFO] 🔄 Initiating reconnection...
15:21:23 [ERROR] ❌ Reconnection failed
15:21:53 [INFO] 🔄 Initiating reconnection...
15:22:23 [ERROR] ❌ Reconnection failed
```

**원인**: 근본적인 네트워크 문제
**해결**:
- WiFi 라우터 재부팅
- AP Isolation 설정 확인
- 같은 서브넷인지 확인

## 성공 기준

✅ **WiFi 10초 끊김 후 30초 내 자동 복구**
✅ **프레임 수신 재개**
✅ **추가 사용자 개입 없음**

## 강제 끊김 테스트 방법

### 방법 1: WiFi On/Off (가장 간단)
```
iPhone: WiFi Off → 10초 대기 → WiFi On
```

### 방법 2: Airplane Mode
```
iPhone: Airplane Mode On → 10초 → Airplane Mode Off
```

### 방법 3: 서버 재시작
```bash
# 서버 터미널에서
Ctrl+C  (서버 종료)
npm start  (서버 재시작)
```

### 방법 4: Python 재시작
```bash
# Python 터미널에서
Ctrl+C  (종료)
python3 rtmlib_webrtc_receiver_simple.py  (재시작)
```

## 다음 단계

재연결이 성공하면:
1. **장시간 테스트**: 5-10분 동안 안정성 확인
2. **반복 테스트**: 여러 번 끊었다 연결 테스트
3. **실제 사용**: RTMLib 바디 트래킹 추가

재연결이 실패하면:
1. 로그 전체 확인
2. 네트워크 환경 점검
3. 라우터 설정 확인 (AP Isolation 등)

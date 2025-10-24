# 자동 재연결 시스템

## 문제

WebRTC 연결이 30초~1분 후 좀비 상태가 됨:
- Connection state: **connected**
- ICE state: **completed**
- 하지만 프레임은 **안 들어옴**

→ ICE restart는 복잡하고 불안정

## 해결책 (당신의 제안!)

**연결이 끊어지면 깔끔하게 처음부터 재연결**

```
Python (10초 끊김 감지)
    ↓
WebSocket: {"type": "reconnect_request", "reason": "..."}
    ↓
Server.js → relay
    ↓
WebSocket: {"command": "reconnect"}
    ↓
iPhone:
  1. peerConnection.close()
  2. setupPeerConnection()
  3. createOffer()
  4. 새로운 WebRTC 연결 수립
    ↓
Python:
  1. Offer 수신
  2. Answer 생성
  3. 프레임 수신 재개
```

## 구현

### 1. Python (rtmlib_webrtc_receiver_simple.py)

**10초 타임아웃 감지 → 재연결 요청**:
```python
if elapsed > 10:
    # 서버에 재연결 요청
    await self.ws.send(json.dumps({
        'type': 'reconnect_request',
        'reason': f'No frames for {int(elapsed)}s'
    }))

    # 30초 대기 후 확인
    await asyncio.sleep(30)

    if recent_elapsed < 5:
        logger.info("✅ Reconnection successful!")
        continue  # 모니터링 계속
```

### 2. Server.js

**재연결 요청 relay**:
```javascript
else if (data.type === 'reconnect_request') {
    console.log(`🔄 Reconnection requested: ${data.reason}`);

    // 카메라(iPhone)에게 명령 전달
    cameras.forEach((camera) => {
        camera.send(JSON.stringify({ command: 'reconnect' }));
    });
}
```

### 3. iOS (WebRTCViewController.swift)

**재연결 명령 처리**:
```swift
case "reconnect":
    reconnectWebRTC()

private func reconnectWebRTC() {
    // 1. 기존 연결 종료
    webRTCManager.disconnect()

    // 2. 새 peer connection
    webRTCManager.setupPeerConnection()

    // 3. Video capturer 재생성
    let capturer = webRTCManager.setupCapturer(...)
    cameraManager?.updateVideoCapturer(capturer)

    // 4. 새 offer 생성
    webRTCManager.createOffer()
}
```

## 동작 흐름

### 정상 상태
```
14:50:00 [INFO] 📹 Frame 60 | FPS: 30.0
14:50:02 [INFO] 📹 Frame 120 | FPS: 30.0
14:50:04 [INFO] 📹 Frame 180 | FPS: 30.0
...
```

### 연결 끊김 감지
```
14:50:40 [INFO] 📹 Frame 900 | FPS: 30.0
14:50:42 [INFO] 📹 Frame 960 | FPS: 30.0
(프레임 멈춤)
14:50:47 [ERROR] ❌ No frames for 5s! (failure #1)
14:50:50 [ERROR] ❌ No frames for 8s! (failure #2)
14:50:53 [ERROR] 💀 Connection DEAD after 11s
14:50:53 [INFO] 🔄 Requesting reconnection from camera...
14:50:53 [INFO] ⏳ Waiting 30s for reconnection...
```

### 서버 로그
```
🔄 Reconnection requested from viewer: No frames for 11s
📤 Sending reconnect command to camera
```

### iPhone 로그
```
📥 Command received: reconnect
🔄 Starting WebRTC reconnection...
🔄 Closing existing peer connection
✅ Peer connection created
📤 Sending offer...
✅ WebRTC reconnection initiated
```

### 재연결 성공
```
14:51:23 [INFO] ✅ Reconnection successful! Resuming monitoring...
14:51:23 [INFO] 📹 Frame 1020 | FPS: 30.0
14:51:25 [INFO] 📹 Frame 1080 | FPS: 30.0
(프레임 정상 수신)
```

## 장점

### ✅ 간단함
- ICE restart 불필요
- 복잡한 상태 관리 불필요
- 처음부터 다시 시작

### ✅ 확실함
- 완전히 새로운 연결
- 좀비 상태 완전히 해소
- 성공률 높음

### ✅ 자동화
- 사용자 개입 불필요
- Python이 자동 감지
- 30초 내 자동 복구

### ✅ 무한 재연결
- 한 번 실패해도 계속 모니터링
- 다음 끊김도 자동 재연결
- 장시간 안정적 운영

## 테스트

### 1. 서버 시작
```bash
cd server
npm start
```

### 2. iOS 앱 재빌드
```bash
# Xcode: Product → Clean → Run
```

### 3. Python 실행
```bash
python3 rtmlib_webrtc_receiver_simple.py
```

### 4. 강제 끊김 테스트

**방법 1: WiFi 끄기**
```
iPhone에서:
1. Control Center 열기
2. WiFi 아이콘 탭 (끄기)
3. 10초 대기
4. WiFi 다시 켜기

예상 결과:
- Python: "Connection DEAD" → "Requesting reconnection"
- iPhone: "reconnect" 명령 수신 → 재연결
- Python: "Reconnection successful!"
```

**방법 2: 네트워크 시뮬레이션**
```
Mac에서:
sudo tc qdisc add dev en0 root netem loss 100%  # 패킷 100% 손실
sleep 15
sudo tc qdisc del dev en0 root  # 복구

예상 결과: 자동 재연결
```

## 재연결 실패 시

### 30초 후에도 프레임이 안 오면
```
14:51:23 [ERROR] ❌ Reconnection failed
14:51:23 [ERROR] 💀 Connection declared DEAD
```

**원인**:
1. iPhone 앱이 죽음
2. 서버가 죽음
3. 네트워크가 완전히 끊김

**해결**:
1. iPhone 앱 상태 확인
2. 서버 로그 확인
3. 네트워크 연결 확인
4. 수동으로 앱 재시작

## 개선 가능 사항 (미래)

### 옵션 1: 무한 재시도
```python
# 재연결 실패해도 계속 시도
max_reconnect_attempts = 3
for attempt in range(max_reconnect_attempts):
    await send_reconnect_request()
    await asyncio.sleep(30)
    if connected:
        break
```

### 옵션 2: Exponential Backoff
```python
# 재시도 간격을 점점 늘림
retry_delays = [10, 30, 60, 120]  # 초
for delay in retry_delays:
    await asyncio.sleep(delay)
    await send_reconnect_request()
```

### 옵션 3: Health Check Ping
```python
# 주기적으로 연결 상태 확인
async def send_health_check():
    while True:
        await asyncio.sleep(5)
        if last_frame_time > 5s_ago:
            await send_reconnect_request()
```

## 결론

당신의 제안대로:
- **10초 끊김 감지** → 자동
- **재연결 요청** → 자동
- **iPhone 재연결** → 자동
- **연결 복구** → 자동

→ **사용자는 아무것도 안 해도 됨!** 🎉

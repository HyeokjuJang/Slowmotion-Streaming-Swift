# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an iOS SlowMotion camera app with **WebSocket streaming** capability. The app records high-fps video (60/120/240fps) locally while simultaneously streaming to a browser viewer via WebSocket. The system uses a Node.js server to relay video frames and handle video uploads.

**Current Architecture**: WebSocket-based JPEG/H.264 streaming (primary method)
**Legacy Support**: WebRTC streaming code is preserved but not actively used due to frequent reconnection issues (5-second delays on each reconnect)

## Key Architecture

### Dual-Stream System
The app uses **separate frame rates** for recording and streaming:
- **Recording**: Captures at user-selected FPS (60/120/240) for high-quality slow-motion playback
- **WebRTC Streaming**: Sends every Nth frame at 30fps to browser (e.g., 120fps → 30fps = skip 3 out of 4 frames)

This is implemented in `WebRTCCameraManager.swift`:
```swift
let frameSkipRatio = Int(recordingFPS / webrtcStreamingFPS)  // e.g., 120/30 = 4
frameSkipCounter += 1
if frameSkipCounter % frameSkipRatio != 0 {
    return  // Skip this frame for WebRTC
}
```

### WebRTC Architecture
- **iOS**: Acts as the WebRTC **offerer** (creates offer, sends to server)
- **Browser**: Acts as the WebRTC **answerer** (receives offer, sends answer back)
- **Server**: Pure signaling relay - forwards WebRTC messages (offer/answer/ICE candidates) between iOS and browser
- **Connection**: Direct P2P connection between iOS and browser after signaling completes

Critical: The server does NOT process video frames. WebRTC video flows directly from iOS to browser.

### WebRTC Bitrate Limitation
WebRTC streaming stops after ~30-60 seconds without bitrate limits due to bandwidth estimation failures. The `WebRTCManager.swift` modifies SDP to add bitrate constraints:

```swift
private func setMaxBitrate(sdp: RTCSessionDescription, maxBitrate: Int) -> RTCSessionDescription
```

This adds `b=AS:2000` (2 Mbps) to the SDP video section, preventing connection failure from unlimited bitrate attempts.

### WebSocket Communication Patterns

**Two separate WebSocket connections:**

1. **Camera WebSocket** (`ws://server:8080/camera`)
   - Status updates: `{"type": "status", "status": "waiting|recording|uploading"}`
   - WebRTC signaling: `{"type": "offer|ice", "sdp": "...", "candidate": "..."}`
   - Control commands (received): `{"command": "start|stop"}`

2. **Viewer WebSocket** (`ws://server:8080/viewer`)
   - WebRTC signaling: `{"type": "answer|ice", "sdp": "...", "candidate": "..."}`
   - Control commands (sent): `{"command": "start|stop"}`

The server in `server.js` routes messages between camera and viewer connections.

## Common Commands

### Server
```bash
cd server
npm install          # Install dependencies
npm start            # Start production server (port 3000 HTTP, 8080 WebSocket)
npm run dev          # Start with nodemon for development

# Server endpoints:
# http://localhost:3000/viewer-webrtc.html - Browser viewer
# ws://localhost:8080/camera - Camera WebSocket
# ws://localhost:8080/viewer - Viewer WebSocket
```

### iOS App
```bash
# Build and run in Xcode
# Product → Run (⌘R)

# The app requires:
# 1. Physical iOS device (camera not available in simulator)
# 2. USB connection or same WiFi network as server
# 3. Server URL configured in Settings tab (e.g., ws://192.168.1.100:8080/camera)
```

**Important**: The iOS app connects to the server's IP address, not `localhost`, since it runs on a separate device.

## Critical iOS Components

### WebRTCViewController.swift
Orchestrates the entire WebRTC + camera system:
- Manages `WebRTCManager`, `WebRTCCameraManager`, `WebSocketManager`
- Handles state transitions: disconnected → connected → streaming → recording
- Routes WebRTC signaling messages between WebSocket and WebRTC peer connection
- Coordinates recording start/stop with camera and video writer

### WebRTCCameraManager.swift
Handles AVFoundation camera capture and video recording:
- **Dual output**: Sends frames to both WebRTC (via `RTCVideoCapturer`) and local video writer (`AVAssetWriter`)
- **Frame skipping**: Implements the 120fps→30fps decimation for WebRTC
- **Recording**: Manages `.mov` file creation with correct FPS metadata
- **Preview**: Provides `AVCaptureVideoPreviewLayer` for SwiftUI view

Key methods:
- `setupCamera(fps:resolution:videoCapturer:webrtcStreamingFPS:)` - Configures dual-rate capture
- `sendFrameToWebRTC(_:)` - Applies frame skipping and forwards to WebRTC
- `startRecording()` / `stopRecording()` - Manages local video file

### WebRTCManager.swift
Manages the RTCPeerConnection:
- **SDP modification**: Adds bitrate limits to prevent 30-second timeout issue
- **ICE gathering**: Uses `continualGatheringPolicy = .gatherContinually` to keep connection alive
- **Delegates**: Notifies controller of connection state changes and ICE candidates

**Recent fix**: Added `setMaxBitrate()` to modify SDP and add `b=AS:2000` (2 Mbps limit).

### WebSocketManager.swift
Handles WebSocket connection to signaling server:
- Auto-reconnection with exponential backoff
- Message routing: JSON parsing for signaling vs. commands
- Delegate pattern for event propagation to controller

## Known Issues & Solutions

### Issue 1: WebRTC Streaming Stops After 30-60 Seconds
**Cause**: WebRTC attempts unlimited bitrate for 720p@30fps, causing bandwidth estimation failure and connection drop.

**Solution**: `WebRTCManager.swift` now modifies SDP to add bitrate constraints (`b=AS:2000` for 2 Mbps). This was added in the `createOffer()` method.

**Verification**: Check SDP logs for `b=AS:` lines in Xcode console.

### Issue 2: Black Camera Preview
**Cause**: Missing `NSCameraUsageDescription` in `Info.plist`.

**Solution**: Already added to `Info.plist`. If preview is still black, check:
1. Camera permissions in iOS Settings
2. `AVCaptureDevice.authorizationStatus(for: .video)` returns `.authorized`
3. Preview layer frame is non-zero (check `WebRTCCameraView.swift`)

### Issue 3: Browser Autoplay Policy Blocks Video
**Cause**: Browsers block autoplay of unmuted video.

**Solution**: `viewer-webrtc.html` includes `muted` attribute on `<video>` element:
```html
<video id="remoteVideo" autoplay playsinline muted></video>
```

### Issue 4: WebRTC Frequent Reconnections (Why WebSocket is Now Primary)
**Cause**: WebRTC connection drops frequently due to network instability, ICE candidate failures, or mobile network switching.

**Problem**: Each reconnection takes ~5 seconds (ICE gathering + offer/answer exchange + connection establishment), causing unacceptable interruptions.

**Solution**: Reverted to WebSocket streaming as primary method:
- WebSocket reconnection is faster (~1-2 seconds)
- More resilient to network fluctuations
- Simpler connection model without P2P complexity

**Status**: WebRTC code is preserved in codebase for future use or specific scenarios, but WebSocket is the default streaming method.

## WebRTC Debugging

### iOS Side (Xcode Console)
Look for these log patterns:
```
✅ Offer created with bitrate limit and set as local description
🧊 ICE candidate generated
🧊 ICE connection state: 2 (connected)
📹 WebRTC frames sent: 1800 (skipped 5400 frames)  # 30fps with 120fps source
```

### Browser Side (Console)
```javascript
// Stats monitoring shows:
// - framesReceived: increasing counter
// - fps: should be ~30
// - ICE state: "connected"
```

### Server Side
```
📡 WebRTC signaling from camera: offer
📡 WebRTC signaling from viewer: answer
📡 WebRTC signaling from camera: ice
```

**Red flag**: If you see ICE candidates but no video after 30 seconds, check bitrate limiting in iOS SDP.

## Testing WebRTC Connection

1. Start server: `cd server && npm start`
2. Open browser: `http://localhost:3000/viewer-webrtc.html`
3. Run iOS app on physical device
4. Configure server URL in iOS Settings: `ws://<server-ip>:8080/camera`
5. Tap "연결" in iOS app
6. Browser should show video within 5 seconds
7. Verify stats show FPS ~30 and increasing frame count

**If video doesn't appear:**
- Check Xcode console for "❌" error logs
- Check browser console for WebRTC errors
- Check server terminal for signaling message flow
- Verify ICE connection state reaches "connected" in both iOS and browser

## File Architecture Notes

### Constants.swift
Defines two separate FPS/resolution configs:
- `Constants.Recording`: For local video recording (120fps, 1080p)
- `Constants.WebRTC`: For streaming (30fps, 720p)

These must be kept separate to support dual-stream architecture.

### viewer-webrtc.html
Single-file browser client with:
- WebSocket connection to signaling server
- WebRTC peer connection handling
- Stats monitoring (frames received, FPS calculation)
- Control buttons (start/stop recording)

**Note**: This viewer is WebRTC-based. The old `viewer.html` was WebSocket streaming (deprecated).

## Network Configuration

### iOS App URLs
The app needs TWO URLs configured in Settings:
1. **WebSocket URL**: `ws://<server-ip>:8080/camera` - For signaling and control
2. **Upload URL**: Auto-generated from WebSocket URL, changing port 8080→3000 and path `/camera`→`/upload`

### Firewall Requirements
- Port 3000: HTTP (for viewer web page and video upload)
- Port 8080: WebSocket (for signaling)
- Ephemeral UDP ports: WebRTC media (varies, managed by STUN)

### STUN Servers
Configured in both `WebRTCManager.swift` and `viewer-webrtc.html`:
```
stun:stun.l.google.com:19302
stun:stun1.l.google.com:19302
```

These enable WebRTC NAT traversal for local network connections.

## Performance Considerations

### Frame Processing Pipeline
```
AVCaptureSession (120fps)
    ↓
captureOutput(sampleBuffer)
    ↓
    ├──→ recordFrame() ────────────→ AVAssetWriter (all frames, 120fps)
    ├──→ sendFrameToWebRTC() ──────→ RTCVideoCapturer (every 4th frame, 30fps)
    └──→ updatePreview() ──────────→ AVCaptureVideoPreviewLayer
```

All paths run on `captureQueue` (QoS: `.userInitiated`) to prevent frame drops.

### Memory Management
- `CVPixelBuffer` is not copied; passed by reference to WebRTC
- `CMSampleBuffer` is retained by `AVAssetWriter` during recording
- Preview layer uses zero-copy rendering

### CPU Usage
Typical load on iPhone:
- 120fps capture: ~40-50% CPU
- WebRTC encoding (30fps): ~15-20% CPU
- H.264 recording: ~10-15% CPU (hardware accelerated)

If CPU exceeds 80%, reduce WebRTC resolution or streaming FPS.

## Recent Changes Log

### 2025-10-24: Reverted to WebSocket Streaming (Current Architecture)
- **Status**: **Active - WebSocket is now the primary streaming method**
- **Files**: Using existing WebSocket infrastructure, WebRTC code preserved
- **Change**: Switched from WebRTC back to WebSocket streaming for primary use
- **Reason**: WebRTC has frequent reconnection issues with 5-second delay on each reconnect, making it impractical for production use
- **Impact**:
  - More stable connection with faster recovery
  - Both WebSocket and WebRTC code paths are maintained in codebase
  - WebSocket is default, WebRTC available as fallback option
- **Trade-offs**: Higher latency (~300-500ms) vs WebRTC (~100ms), but much better reliability

### 2025-10-23: Added WebRTC Bitrate Limiting (Legacy)
- **File**: `WebRTCManager.swift`
- **Change**: Added `setMaxBitrate()` method to modify SDP
- **Reason**: Prevent 30-second WebRTC connection timeout due to unlimited bitrate
- **Impact**: WebRTC now stable for extended streaming sessions

### 2025-10-22: Separated Recording and Streaming FPS
- **Files**: `WebRTCCameraManager.swift`, `Constants.swift`
- **Change**: Added frame skipping logic to send 30fps to WebRTC while recording 120fps
- **Reason**: User reported recording FPS was incorrectly dropping to 30fps
- **Impact**: Recording and streaming now have independent frame rates

### 2025-10-21: Switched to WebRTC Streaming
- **Files**: Created `WebRTCManager.swift`, `WebRTCViewController.swift`, `viewer-webrtc.html`
- **Change**: Replaced WebSocket JPEG streaming with WebRTC
- **Reason**: Lower latency, better quality, native browser support
- **Impact**: Latency reduced from ~500ms to ~100ms

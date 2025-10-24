#!/usr/bin/env python3
"""
WebRTC Receiver - 로컬 네트워크 최적화 버전
복잡한 기능 제거, 안정성 우선
"""

import asyncio
import json
import logging
import cv2
import numpy as np
import struct
import time
from aiortc import RTCPeerConnection, RTCSessionDescription, RTCIceCandidate
from av import VideoFrame
import websockets
import av

# ffmpeg 경고 메시지 억제
av.logging.set_level(av.logging.ERROR)

# 설정
SIGNALING_SERVER = "ws://localhost:8080/viewer"
FRAME_SERVER = "ws://localhost:8080/camera"

# 로깅
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%H:%M:%S'
)
logger = logging.getLogger(__name__)


class VideoTransformTrack:
    """비디오 트랙 - 프레임을 받아서 서버로 전송"""
    def __init__(self, track, frame_sender):
        self.track = track
        self.frame_count = 0
        self.frame_sender = frame_sender
        self.last_recv_time = time.time()

    async def recv(self):
        """프레임 수신 및 처리"""
        try:
            frame = await self.track.recv()
            self.last_recv_time = time.time()
            self.frame_count += 1

            # VideoFrame → numpy array 변환
            img = frame.to_ndarray(format="bgr24")

            # 프레임 정보 출력 (60프레임마다)
            if self.frame_count % 60 == 0:
                elapsed = time.time() - getattr(self, 'start_time', time.time())
                if not hasattr(self, 'start_time'):
                    self.start_time = time.time()
                fps = self.frame_count / elapsed if elapsed > 0 else 0
                logger.info(f"📹 Frame {self.frame_count} | FPS: {fps:.1f} | Shape: {img.shape}")

            # 프레임을 WebSocket으로 전송
            await self.frame_sender(img)

            return frame

        except Exception as e:
            logger.error(f"❌ Error receiving frame: {e}")
            raise


class WebRTCReceiver:
    def __init__(self):
        # 로컬 네트워크용 최소 설정 - STUN 없음
        self.pc = RTCPeerConnection()
        self.ws = None
        self.frame_ws = None
        self.video_track = None
        self.connection_dead = False

    async def connect_frame_server(self):
        """프레임 전송 서버 연결"""
        try:
            logger.info(f"Connecting to frame server: {FRAME_SERVER}")
            self.frame_ws = await websockets.connect(FRAME_SERVER)
            logger.info("✅ Connected to frame server")
        except Exception as e:
            logger.error(f"Failed to connect to frame server: {e}")

    async def send_frame(self, img):
        """프레임을 JPEG로 인코딩하여 서버에 전송"""
        if self.frame_ws is None or self.frame_ws.closed:
            return

        try:
            # numpy array → JPEG 인코딩
            _, jpeg_data = cv2.imencode('.jpg', img, [cv2.IMWRITE_JPEG_QUALITY, 85])

            # 타임스탬프 추가
            timestamp = time.time()
            header = struct.pack('<d', timestamp)

            # 전송
            message = header + jpeg_data.tobytes()
            await self.frame_ws.send(message)

        except Exception as e:
            logger.debug(f"Frame send error: {e}")

    async def connect_signaling(self):
        """Signaling 서버 연결"""
        logger.info(f"Connecting to {SIGNALING_SERVER}")

        async with websockets.connect(SIGNALING_SERVER) as ws:
            self.ws = ws
            logger.info("✅ Connected to signaling server")

            # 프레임 전송 서버에도 연결
            await self.connect_frame_server()

            # ICE candidate 이벤트
            @self.pc.on("icecandidate")
            async def on_icecandidate(candidate):
                if candidate:
                    # 모든 candidate 로깅 (디버깅용)
                    logger.info(f"🧊 ICE: type={candidate.type}, ip={candidate.ip}, port={candidate.port}, protocol={candidate.protocol}")
                    await self.send_ice_candidate(candidate)

            # 트랙 수신 이벤트
            @self.pc.on("track")
            async def on_track(track):
                logger.info(f"🎬 Track received: {track.kind}")

                if track.kind == "video":
                    self.video_track = VideoTransformTrack(track, self.send_frame)
                    asyncio.create_task(self.process_frames())
                    asyncio.create_task(self.monitor_connection())

            # 연결 상태 모니터링
            @self.pc.on("connectionstatechange")
            async def on_connectionstatechange():
                state = self.pc.connectionState
                logger.info(f"🔌 Connection state: {state}")

            # ICE 연결 상태 모니터링
            @self.pc.on("iceconnectionstatechange")
            async def on_iceconnectionstatechange():
                ice_state = self.pc.iceConnectionState
                logger.info(f"🧊 ICE state: {ice_state}")

                # 선택된 candidate pair 로깅
                if ice_state == "connected" or ice_state == "completed":
                    logger.info("✅ WebRTC connection established!")

            # 메시지 수신 루프
            async for message in ws:
                try:
                    # 바이너리 메시지 무시
                    if isinstance(message, bytes):
                        continue

                    data = json.loads(message)
                    await self.handle_message(data)
                except json.JSONDecodeError:
                    pass
                except Exception as e:
                    logger.error(f"Error handling message: {e}")

    async def handle_message(self, data):
        """Signaling 메시지 처리"""
        msg_type = data.get('type')

        if msg_type == 'offer':
            logger.info("📥 Received offer")

            offer = RTCSessionDescription(
                sdp=data['sdp'],
                type='offer'
            )
            await self.pc.setRemoteDescription(offer)

            # Answer 생성
            answer = await self.pc.createAnswer()
            await self.pc.setLocalDescription(answer)

            # Answer 전송 (SDP 수정 없음 - 로컬 네트워크용)
            await self.ws.send(json.dumps({
                'type': 'answer',
                'sdp': self.pc.localDescription.sdp
            }))
            logger.info("📤 Sent answer")

        elif msg_type == 'ice':
            # ICE candidate 처리
            candidate_data = data.get('candidate')

            if isinstance(candidate_data, dict):
                candidate_str = candidate_data.get('candidate')
                sdp_mline_index = candidate_data.get('sdpMLineIndex', 0)
            else:
                candidate_str = candidate_data
                sdp_mline_index = data.get('sdpMLineIndex', 0)

            if candidate_str:
                try:
                    parts = candidate_str.split()
                    if len(parts) >= 6:
                        candidate = RTCIceCandidate(
                            foundation=parts[0].replace("candidate:", ""),
                            component=int(parts[1]),
                            protocol=parts[2],
                            priority=int(parts[3]),
                            ip=parts[4],
                            port=int(parts[5]),
                            type=parts[7] if len(parts) > 7 else "host",
                            sdpMid="0",
                            sdpMLineIndex=sdp_mline_index
                        )
                        await self.pc.addIceCandidate(candidate)
                        logger.debug(f"Added ICE candidate: {parts[4]}:{parts[5]}")
                except Exception as e:
                    logger.debug(f"Failed to parse ICE candidate: {e}")

        elif msg_type == 'camera_status':
            logger.info(f"Camera status: {data.get('status')}")

    async def send_ice_candidate(self, candidate):
        """ICE candidate 전송"""
        if self.ws and not self.ws.closed:
            await self.ws.send(json.dumps({
                'type': 'ice',
                'candidate': {
                    'candidate': f"candidate:{candidate.foundation} {candidate.component} "
                                f"{candidate.protocol} {candidate.priority} "
                                f"{candidate.ip} {candidate.port} typ {candidate.type}",
                    'sdpMLineIndex': candidate.sdpMLineIndex
                }
            }))

    async def monitor_connection(self):
        """연결 상태 모니터링"""
        consecutive_failures = 0

        while True:
            await asyncio.sleep(3)

            if self.video_track:
                elapsed = time.time() - self.video_track.last_recv_time

                if elapsed > 5:
                    consecutive_failures += 1
                    logger.error(f"❌ No frames for {int(elapsed)}s! (failure #{consecutive_failures})")
                    logger.error(f"   Connection state: {self.pc.connectionState}")
                    logger.error(f"   ICE state: {self.pc.iceConnectionState}")

                    if elapsed > 10:
                        logger.error(f"💀 Connection DEAD after {int(elapsed)}s")
                        self.connection_dead = True
                        break
                else:
                    if consecutive_failures > 0:
                        logger.info(f"✅ Frames resumed after {consecutive_failures} failures")
                        consecutive_failures = 0

    async def process_frames(self):
        """프레임 처리 루프"""
        logger.info("🎬 Starting frame processing...")

        try:
            while True:
                await self.video_track.recv()
        except Exception as e:
            logger.error(f"❌ Frame processing stopped: {e}")
            import traceback
            logger.error(traceback.format_exc())

    async def close(self):
        """연결 종료"""
        await self.pc.close()
        if self.frame_ws and not self.frame_ws.closed:
            await self.frame_ws.close()


async def main():
    logger.info("=== WebRTC Receiver (Simple Local Network Version) ===")
    logger.info("Optimized for same WiFi network")
    logger.info("No STUN/TURN, no complex features")

    receiver = WebRTCReceiver()

    try:
        await receiver.connect_signaling()
    except KeyboardInterrupt:
        logger.info("\n⚠️  Interrupted by user")
    finally:
        await receiver.close()

        if receiver.connection_dead:
            logger.error("\n" + "="*60)
            logger.error("💀 Connection failed")
            logger.error("Check the logs above for ICE candidate info")
            logger.error("="*60)


if __name__ == '__main__':
    asyncio.run(main())

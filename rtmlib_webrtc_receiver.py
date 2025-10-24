#!/usr/bin/env python3
"""
WebRTC Receiver for RTMLib Body Tracking
Uses aiortc for pure Python WebRTC implementation
"""

import asyncio
import json
import logging
import cv2
import numpy as np
import struct
import time
from aiortc import RTCPeerConnection, RTCSessionDescription, RTCIceCandidate, RTCConfiguration, RTCIceServer
from aiortc.contrib.media import MediaRecorder, MediaRelay
from av import VideoFrame
import websockets
import av

# ffmpeg 경고 메시지 억제
av.logging.set_level(av.logging.ERROR)

# 설정
SIGNALING_SERVER = "ws://localhost:8080/viewer"
FRAME_SERVER = "ws://localhost:8080/camera"  # 프레임을 전송할 서버 (카메라처럼)

# 로깅
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%H:%M:%S'
)
logger = logging.getLogger(__name__)


class VideoTransformTrack:
    """
    비디오 트랙 - 프레임을 받아서 RTMLib 처리
    """
    def __init__(self, track, frame_sender):
        self.track = track
        self.frame_count = 0
        self.frame_sender = frame_sender  # WebSocket 프레임 전송 콜백
        self.last_recv_time = time.time()  # 마지막 프레임 수신 시간

    async def recv(self):
        """프레임 수신 및 처리"""
        try:
            frame = await self.track.recv()
            self.last_recv_time = time.time()  # 수신 시간 업데이트

            self.frame_count += 1

            # VideoFrame → numpy array 변환
            img = frame.to_ndarray(format="bgr24")

            # 프레임 정보 출력 (60프레임마다 = 2초마다)
            if self.frame_count % 60 == 0:
                elapsed = time.time() - getattr(self, 'start_time', time.time())
                if not hasattr(self, 'start_time'):
                    self.start_time = time.time()
                fps = self.frame_count / elapsed if elapsed > 0 else 0
                logger.info(f"📹 Frame {self.frame_count} | FPS: {fps:.1f} | Shape: {img.shape}")
        except Exception as e:
            logger.error(f"❌ Error receiving frame {self.frame_count}: {e}")
            raise  # 예외를 다시 던져서 process_frames에서 처리

        # TODO: 여기서 RTMLib 바디 트래킹 처리
        # import rtmpose
        # results = rtmpose.inference(img)
        # keypoints = results.pred_instances.keypoints
        #
        # # 키포인트 시각화
        # for kp in keypoints:
        #     x, y = int(kp[0]), int(kp[1])
        #     cv2.circle(img, (x, y), 5, (0, 255, 0), -1)

        # 프레임을 WebSocket으로 전송 (viewer.html에서 볼 수 있도록)
        await self.frame_sender(img)

        # 처리된 프레임 반환 (필요시)
        return frame


class WebRTCReceiver:
    def __init__(self):
        # 로컬 네트워크용 간단한 설정
        # STUN만 사용 (TURN은 선택사항)
        config = RTCConfiguration(
            iceServers=[
                RTCIceServer(urls=["stun:stun.l.google.com:19302"])
            ]
        )
        self.pc = RTCPeerConnection(configuration=config)
        self.ws = None  # Signaling WebSocket
        self.frame_ws = None  # Frame transmission WebSocket
        self.video_track = None
        self.data_channel = None  # Keep-alive용 Data Channel
        self.frame_send_errors = 0
        self.last_error_log_time = 0
        self.ice_restart_count = 0
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
            current_time = time.time()
            # 5초마다 한 번만 경고
            if current_time - self.last_error_log_time > 5:
                logger.warning("⚠️ Frame WebSocket is closed, cannot send frames")
                self.last_error_log_time = current_time
            return

        try:
            # numpy array → JPEG 인코딩
            _, jpeg_data = cv2.imencode('.jpg', img, [cv2.IMWRITE_JPEG_QUALITY, 85])

            # 타임스탬프 추가 (8바이트 double, little-endian)
            timestamp = time.time()
            header = struct.pack('<d', timestamp)

            # 전송: [timestamp(8 bytes)] + [JPEG data]
            message = header + jpeg_data.tobytes()
            await self.frame_ws.send(message)

            # 에러 카운터 리셋
            if self.frame_send_errors > 0:
                logger.info(f"✅ Frame sending resumed after {self.frame_send_errors} errors")
                self.frame_send_errors = 0

        except Exception as e:
            self.frame_send_errors += 1
            current_time = time.time()
            # 5초마다 또는 처음 에러일 때만 로그
            if self.frame_send_errors == 1 or current_time - self.last_error_log_time > 5:
                logger.error(f"❌ Failed to send frame (error #{self.frame_send_errors}): {e}")
                self.last_error_log_time = current_time

    async def connect_signaling(self):
        """Signaling 서버 연결"""
        logger.info(f"Connecting to {SIGNALING_SERVER}")

        async with websockets.connect(SIGNALING_SERVER) as ws:
            self.ws = ws
            logger.info("✅ Connected to signaling server")

            # 프레임 전송 서버에도 연결
            await self.connect_frame_server()

            # ICE candidate 이벤트 설정
            @self.pc.on("icecandidate")
            async def on_icecandidate(candidate):
                if candidate:
                    # IPv6 candidate 필터링
                    if ':' in candidate.ip and not candidate.ip.startswith('::ffff:'):
                        logger.debug(f"Skipping IPv6 ICE candidate: {candidate.ip}")
                        return

                    # Candidate 타입 로깅 (디버깅용)
                    logger.info(f"🧊 ICE candidate: type={candidate.type}, ip={candidate.ip}, port={candidate.port}")
                    await self.send_ice_candidate(candidate)

            # Data Channel 수신 이벤트 (iPhone이 생성한 채널 받기)
            @self.pc.on("datachannel")
            def on_datachannel(channel):
                logger.info(f"📡 Data channel received: {channel.label}")
                self.data_channel = channel

                @channel.on("open")
                def on_open():
                    logger.info("📡 Data channel opened for keep-alive")
                    asyncio.create_task(self.send_keepalive())

                @channel.on("message")
                def on_message(message):
                    logger.debug(f"💓 Keep-alive pong received: {message}")

            # 트랙 수신 이벤트
            @self.pc.on("track")
            async def on_track(track):
                logger.info(f"🎬 Track received: {track.kind}")

                if track.kind == "video":
                    self.video_track = VideoTransformTrack(track, self.send_frame)

                    # 프레임 수신 시작
                    asyncio.create_task(self.process_frames())

                    # 연결 모니터링 시작
                    asyncio.create_task(self.monitor_connection())

            # 연결 상태 모니터링
            @self.pc.on("connectionstatechange")
            async def on_connectionstatechange():
                state = self.pc.connectionState
                if state == "connected":
                    logger.info(f"🔌 Connection state: {state}")
                elif state == "disconnected" or state == "failed" or state == "closed":
                    logger.error(f"❌ Connection state: {state}")
                else:
                    logger.info(f"🔌 Connection state: {state}")

            # ICE 연결 상태 모니터링
            @self.pc.on("iceconnectionstatechange")
            async def on_iceconnectionstatechange():
                ice_state = self.pc.iceConnectionState
                if ice_state == "connected" or ice_state == "completed":
                    logger.info(f"🧊 ICE state: {ice_state}")
                elif ice_state == "disconnected" or ice_state == "failed" or ice_state == "closed":
                    logger.error(f"❌ ICE state: {ice_state}")
                else:
                    logger.info(f"🧊 ICE state: {ice_state}")

            # 메시지 수신 루프
            async for message in ws:
                try:
                    # 바이너리 메시지는 무시 (signaling은 JSON만 처리)
                    if isinstance(message, bytes):
                        logger.debug(f"Ignoring binary message ({len(message)} bytes)")
                        continue

                    data = json.loads(message)
                    await self.handle_message(data)
                except json.JSONDecodeError as e:
                    logger.debug(f"Non-JSON message ignored: {str(message)[:50]}")
                except Exception as e:
                    logger.error(f"Error handling message: {e}")

    async def handle_message(self, data):
        """Signaling 메시지 처리"""
        msg_type = data.get('type')

        if msg_type == 'offer':
            logger.info("📥 Received offer")

            # Offer 설정
            offer = RTCSessionDescription(
                sdp=data['sdp'],
                type='offer'
            )
            await self.pc.setRemoteDescription(offer)

            # Answer 생성
            answer = await self.pc.createAnswer()
            await self.pc.setLocalDescription(answer)

            # SDP에서 IPv6 candidate 제거 (안정성 향상)
            sdp_lines = self.pc.localDescription.sdp.split('\r\n')
            filtered_sdp_lines = []
            for line in sdp_lines:
                # IPv6 주소가 포함된 candidate 라인 필터링
                if line.startswith('a=candidate:') and (':' in line.split(' ')[4]):
                    # IPv6 주소 (콜론 포함) 스킵
                    logger.debug(f"Filtering IPv6 candidate: {line[:60]}...")
                    continue
                filtered_sdp_lines.append(line)

            filtered_sdp = '\r\n'.join(filtered_sdp_lines)

            # Answer 전송
            await self.ws.send(json.dumps({
                'type': 'answer',
                'sdp': filtered_sdp
            }))
            logger.info("📤 Sent answer (IPv6 candidates filtered)")

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
                # aiortc는 candidate 문자열을 파싱해야 함
                candidate = RTCIceCandidate(
                    foundation=None,
                    component=1,
                    protocol="udp",
                    priority=0,
                    ip="0.0.0.0",
                    port=0,
                    type="host",
                    relatedAddress=None,
                    relatedPort=None,
                    sdpMid=str(sdp_mline_index),
                    sdpMLineIndex=sdp_mline_index
                )

                # Candidate 문자열 파싱 (간단 버전)
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
                        logger.debug(f"🧊 Added ICE candidate")
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
            logger.debug("🧊 Sent ICE candidate")

    async def send_keepalive(self):
        """WebRTC Data Channel로 주기적 keep-alive 전송"""
        logger.info("🔄 Starting keep-alive loop (10s interval)")
        ping_count = 0

        while not self.connection_dead:
            try:
                await asyncio.sleep(10)  # 10초마다

                if self.data_channel and self.data_channel.readyState == "open":
                    ping_count += 1
                    message = f"ping_{ping_count}_{int(time.time())}"
                    self.data_channel.send(message)
                    logger.debug(f"💓 Keep-alive sent: {message}")
                else:
                    logger.warning("⚠️ Data channel not open, skipping keep-alive")
                    break

            except Exception as e:
                logger.error(f"❌ Keep-alive error: {e}")
                break

        logger.info("Keep-alive loop stopped")

    async def monitor_connection(self):
        """연결 상태를 주기적으로 모니터링"""
        consecutive_failures = 0

        while True:
            await asyncio.sleep(3)  # 3초마다 체크

            if self.video_track:
                elapsed = time.time() - self.video_track.last_recv_time

                if elapsed > 5:
                    consecutive_failures += 1
                    logger.error(f"❌ No frames for {int(elapsed)}s! (failure #{consecutive_failures})")
                    logger.error(f"   Connection state: {self.pc.connectionState}")
                    logger.error(f"   ICE state: {self.pc.iceConnectionState}")
                    logger.error(f"   Last frame: {self.video_track.frame_count}")

                    # 10초 이상 프레임이 없으면 연결 죽은 것으로 판단
                    if elapsed > 10:
                        logger.error(f"💀 Connection declared DEAD after {int(elapsed)}s")
                        self.connection_dead = True
                        break
                else:
                    # 프레임이 다시 들어오면 카운터 리셋
                    if consecutive_failures > 0:
                        logger.info(f"✅ Frame reception resumed after {consecutive_failures} failures")
                        consecutive_failures = 0

    async def process_frames(self):
        """프레임 처리 루프"""
        logger.info("🎬 Starting frame processing...")

        try:
            while True:
                frame = await self.video_track.recv()
                # 프레임은 VideoTransformTrack에서 이미 처리됨

        except asyncio.CancelledError:
            logger.info("Frame processing cancelled")
            raise
        except Exception as e:
            logger.error(f"❌ Frame processing stopped: {e}")
            logger.error(f"   Exception type: {type(e).__name__}")
            logger.error(f"   Connection state: {self.pc.connectionState}")
            logger.error(f"   ICE connection state: {self.pc.iceConnectionState}")
            logger.error(f"   ICE gathering state: {self.pc.iceGatheringState}")
            import traceback
            logger.error(f"   Traceback: {traceback.format_exc()}")

    async def close(self):
        """연결 종료"""
        await self.pc.close()
        if self.frame_ws and not self.frame_ws.closed:
            await self.frame_ws.close()


async def main():
    logger.info("=== WebRTC Receiver for RTMLib ===")
    logger.info("Waiting for iPhone connection...")

    receiver = WebRTCReceiver()

    try:
        await receiver.connect_signaling()
    except KeyboardInterrupt:
        logger.info("\n⚠️  Interrupted by user")
    finally:
        await receiver.close()

        if receiver.connection_dead:
            logger.error("\n" + "="*60)
            logger.error("💀 WebRTC connection died")
            logger.error("="*60)
            logger.error("Possible causes:")
            logger.error("  - Network changed (WiFi → Cellular, or vice versa)")
            logger.error("  - NAT/Firewall timeout")
            logger.error("  - iPhone app went to background")
            logger.error("\nSolution:")
            logger.error("  1. Check iPhone app is still running")
            logger.error("  2. Restart this Python script")
            logger.error("  3. Reconnect from iPhone app")
            logger.error("="*60)


if __name__ == '__main__':
    asyncio.run(main())

const WebSocket = require('ws');
const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs');

const app = express();
const PORT = 3000;
const WS_PORT = 8080;

// 업로드 디렉토리 생성
const uploadsDir = path.join(__dirname, 'uploads');
if (!fs.existsSync(uploadsDir)) {
    fs.mkdirSync(uploadsDir, { recursive: true });
}

// Multer 설정 (파일 업로드)
const storage = multer.diskStorage({
    destination: (req, file, cb) => {
        cb(null, uploadsDir);
    },
    filename: (req, file, cb) => {
        const timestamp = Date.now();
        const ext = path.extname(file.originalname);
        cb(null, `video_${timestamp}${ext}`);
    },
});

const upload = multer({ storage });

// WebSocket 서버
const wss = new WebSocket.Server({ port: WS_PORT });

// 연결된 클라이언트 관리
let cameras = new Map();
let viewers = new Map();

wss.on('connection', (ws, req) => {
    const url = req.url;
    console.log(`New connection: ${url}`);

    if (url.includes('/camera')) {
        handleCameraConnection(ws);
    } else if (url.includes('/viewer')) {
        handleViewerConnection(ws);
    } else {
        ws.close();
    }
});

// 카메라 연결 처리
function handleCameraConnection(ws) {
    const id = Date.now();
    cameras.set(id, ws);
    console.log(`📱 Camera connected: ${id}`);

    ws.on('message', (message) => {
        // 모든 메시지를 Buffer로 변환
        const messageBuffer = Buffer.isBuffer(message)
            ? message
            : Buffer.from(message);

        // JSON 파싱 시도
        try {
            const messageStr = messageBuffer.toString('utf8');
            const data = JSON.parse(messageStr);

            console.log(
                `📥 Camera JSON message: ${
                    data.type || data.status || 'unknown'
                }`
            );

            // WebRTC 시그널링 메시지 (offer, answer, ice)
            if (
                data.type === 'offer' ||
                data.type === 'answer' ||
                data.type === 'ice'
            ) {
                console.log(`📡 WebRTC signaling from camera: ${data.type}`);

                // 모든 뷰어에게 시그널링 전달
                viewers.forEach((viewer) => {
                    if (viewer.readyState === WebSocket.OPEN) {
                        viewer.send(messageStr);
                    }
                });
            }
            // 상태 메시지
            else if (data.status) {
                console.log(`📊 Camera ${id} status: ${data.status}`);

                // 뷰어에게도 상태 전달
                viewers.forEach((viewer) => {
                    if (viewer.readyState === WebSocket.OPEN) {
                        viewer.send(
                            JSON.stringify({
                                type: 'camera_status',
                                cameraId: id,
                                status: data.status,
                            })
                        );
                    }
                });
            }
        } catch (error) {
            // JSON 파싱 실패 = 비디오 프레임 (바이너리)
            if (messageBuffer.length > 1000) {
                // 비디오 프레임 → 모든 뷰어에게 전달
                viewers.forEach((viewer) => {
                    if (viewer.readyState === WebSocket.OPEN) {
                        viewer.send(messageBuffer);
                    }
                });
                // console.log(`📹 Frame relayed: ${messageBuffer.length} bytes`);
            } else {
                console.error('Failed to parse message:', error);
                console.error(
                    'Message was:',
                    messageBuffer.toString().substring(0, 500)
                );
            }
        }
    });

    ws.on('close', () => {
        cameras.delete(id);
        console.log(`📱 Camera disconnected: ${id}`);
    });

    ws.on('error', (error) => {
        console.error(`❌ Camera ${id} error:`, error);
    });
}

// 뷰어 연결 처리
function handleViewerConnection(ws) {
    const id = Date.now();
    viewers.set(id, ws);
    console.log(`👁️  Viewer connected: ${id}`);

    ws.on('message', (message) => {
        try {
            const data = JSON.parse(message.toString());

            // WebRTC 시그널링 메시지 (answer, ice from viewer)
            if (data.type === 'answer' || data.type === 'ice') {
                console.log(`📡 WebRTC signaling from viewer: ${data.type}`);

                // 카메라에게 시그널링 전달
                cameras.forEach((camera) => {
                    if (camera.readyState === WebSocket.OPEN) {
                        camera.send(message.toString());
                    }
                });
            }
            // 제어 명령
            else if (data.command) {
                console.log(`📩 Viewer ${id} command:`, data.command);

                // 뷰어에서 카메라로 명령 전달
                cameras.forEach((camera) => {
                    if (camera.readyState === WebSocket.OPEN) {
                        camera.send(JSON.stringify({ command: data.command }));
                    }
                });
            }
        } catch (error) {
            console.error('Failed to parse viewer message:', error);
        }
    });

    ws.on('close', () => {
        viewers.delete(id);
        console.log(`👁️  Viewer disconnected: ${id}`);
    });

    ws.on('error', (error) => {
        console.error(`❌ Viewer ${id} error:`, error);
    });
}

// Express 미들웨어
app.use(express.json());
app.use(express.static('public'));

// 제어 API
app.post('/control/start', (req, res) => {
    console.log('📡 Start command received');
    cameras.forEach((camera) => {
        if (camera.readyState === WebSocket.OPEN) {
            camera.send(JSON.stringify({ command: 'start' }));
        }
    });
    res.json({ success: true, message: 'Start command sent' });
});

app.post('/control/stop', (req, res) => {
    console.log('📡 Stop command received');
    cameras.forEach((camera) => {
        if (camera.readyState === WebSocket.OPEN) {
            camera.send(JSON.stringify({ command: 'stop' }));
        }
    });
    res.json({ success: true, message: 'Stop command sent' });
});

// 비디오 업로드 API
app.post('/upload', upload.single('video'), (req, res) => {
    if (!req.file) {
        return res
            .status(400)
            .json({ success: false, error: 'No file uploaded' });
    }

    console.log(
        `📤 Video uploaded: ${req.file.filename} (${req.file.size} bytes)`
    );
    res.json({
        success: true,
        filename: req.file.filename,
        size: req.file.size,
        path: `/uploads/${req.file.filename}`,
    });
});

// 업로드된 비디오 목록
app.get('/videos', (req, res) => {
    fs.readdir(uploadsDir, (err, files) => {
        if (err) {
            return res.status(500).json({ success: false, error: err.message });
        }

        const videos = files
            .filter((file) => file.endsWith('.mov') || file.endsWith('.mp4'))
            .map((file) => {
                const stats = fs.statSync(path.join(uploadsDir, file));
                return {
                    filename: file,
                    size: stats.size,
                    created: stats.birthtime,
                };
            })
            .sort((a, b) => b.created - a.created);

        res.json({ success: true, videos });
    });
});

// 업로드된 비디오 제공
app.use('/uploads', express.static(uploadsDir));

// 상태 API
app.get('/status', (req, res) => {
    res.json({
        cameras: cameras.size,
        viewers: viewers.size,
        timestamp: Date.now(),
    });
});

// HTTP 서버 시작
app.listen(PORT, () => {
    console.log(`✅ HTTP server running on http://localhost:${PORT}`);
    console.log(`✅ WebSocket server running on ws://localhost:${WS_PORT}`);
    console.log(`\nEndpoints:`);
    console.log(`  - Camera WebSocket: ws://localhost:${WS_PORT}/camera`);
    console.log(`  - Viewer WebSocket: ws://localhost:${WS_PORT}/viewer`);
    console.log(`  - Viewer page: http://localhost:${PORT}`);
    console.log(`  - Upload API: http://localhost:${PORT}/upload`);
    console.log(
        `  - Control API: http://localhost:${PORT}/control/{start|stop}`
    );
});

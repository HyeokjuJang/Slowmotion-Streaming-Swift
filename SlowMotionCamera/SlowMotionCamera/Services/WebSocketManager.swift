//
//  WebSocketManager.swift
//  SlowMotionCamera
//
//  WebSocket 연결 및 제어 메시지 관리
//

import Foundation
import Starscream

protocol WebSocketManagerDelegate: AnyObject {
    func webSocketDidConnect()
    func webSocketDidDisconnect(error: Error?)
    func webSocketDidReceiveCommand(_ command: String)
    func webSocketDidReceiveSignaling(_ message: SignalingMessage)
}

class WebSocketManager: NSObject, WebSocketDelegate {

    // MARK: - Properties

    weak var delegate: WebSocketManagerDelegate?

    private var socket: WebSocket?
    private var isConnected = false
    private var reconnectTimer: Timer?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = Constants.Network.wsMaxReconnectAttempts
    private let reconnectDelay = Constants.Network.wsReconnectDelay

    // MARK: - Connection Management

    func connect(to urlString: String) {
        guard let url = URL(string: urlString) else {
            print("❌ Invalid WebSocket URL: \(urlString)")
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = Constants.Network.wsTimeout

        socket = WebSocket(request: request)
        socket?.delegate = self
        socket?.connect()

        print("🔵 Connecting to WebSocket: \(urlString)")
    }

    func disconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        reconnectAttempts = 0

        socket?.disconnect()
        socket = nil
        isConnected = false

        print("⚪️ WebSocket disconnected")
    }

    // MARK: - Message Sending

    /// 상태 메시지 전송 (JSON)
    func sendStatus(_ status: String) {
        let message: [String: Any] = [
            "type": "status",
            "status": status,
            "timestamp": Date().timeIntervalSince1970
        ]

        sendJSON(message)
    }

    /// JSON 메시지 전송
    func sendJSON(_ json: [String: Any]) {
        guard isConnected, let socket = socket else {
            print("⚠️ Cannot send message: not connected")
            return
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: json, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                socket.write(string: jsonString, completion: nil)
                print("📤 Sent JSON: \(jsonString)")
            }
        } catch {
            print("❌ Failed to serialize JSON: \(error)")
        }
    }

    /// 바이너리 데이터 전송 (스트리밍용)
    func sendBinaryData(_ data: Data) {
        guard isConnected, let socket = socket else {
            return
        }

        socket.write(data: data)
    }

    /// WebRTC Signaling 메시지 전송
    func sendSignaling(_ message: SignalingMessage) {
        guard isConnected, let socket = socket else {
            print("⚠️ Cannot send signaling: not connected")
            return
        }

        do {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(message)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                socket.write(string: jsonString, completion: nil)
                print("📤 Sent signaling: \(message.type)")
                print("📤 Signaling JSON: \(jsonString.prefix(200))...")
            }
        } catch {
            print("❌ Failed to encode signaling message: \(error)")
        }
    }

    // MARK: - WebSocketDelegate

    func didReceive(event: Starscream.WebSocketEvent, client: Starscream.WebSocketClient) {
        switch event {
        case .connected(let headers):
            handleConnected(headers: headers)

        case .disconnected(let reason, let code):
            handleDisconnected(reason: reason, code: code)

        case .text(let text):
            handleTextMessage(text)

        case .binary(let data):
            handleBinaryMessage(data)

        case .ping(_):
            break

        case .pong(_):
            break

        case .viabilityChanged(let isViable):
            print("🔄 WebSocket viability changed: \(isViable)")

        case .reconnectSuggested(let suggested):
            if suggested {
                attemptReconnect()
            }

        case .cancelled:
            handleDisconnected(reason: "Connection cancelled", code: 0)

        case .error(let error):
            handleError(error)

        case .peerClosed:
            handleDisconnected(reason: "Peer closed", code: 0)
        }
    }

    // MARK: - Event Handlers

    private func handleConnected(headers: [String: String]) {
        print("✅ WebSocket connected")
        isConnected = true
        reconnectAttempts = 0
        reconnectTimer?.invalidate()
        reconnectTimer = nil

        DispatchQueue.main.async {
            self.delegate?.webSocketDidConnect()
        }

        // 연결 직후 waiting 상태 전송
        sendStatus("waiting")
    }

    private func handleDisconnected(reason: String, code: UInt16) {
        print("⚠️ WebSocket disconnected: \(reason) (code: \(code))")
        isConnected = false

        DispatchQueue.main.async {
            self.delegate?.webSocketDidDisconnect(error: nil)
        }

        // 자동 재연결 시도
        if reconnectAttempts < maxReconnectAttempts {
            attemptReconnect()
        } else {
            print("❌ Max reconnect attempts reached")
        }
    }

    private func handleTextMessage(_ text: String) {
        print("📥 Received text: \(text)")

        guard let data = text.data(using: .utf8) else {
            print("⚠️ Failed to convert text to data")
            return
        }

        // WebRTC 시그널링 메시지 확인
        if let signalingMessage = try? JSONDecoder().decode(SignalingMessage.self, from: data) {
            DispatchQueue.main.async {
                self.delegate?.webSocketDidReceiveSignaling(signalingMessage)
            }
            return
        }

        // 제어 명령 확인
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let command = json["command"] as? String {
            DispatchQueue.main.async {
                self.delegate?.webSocketDidReceiveCommand(command)
            }
            return
        }

        print("⚠️ Invalid message format")
    }

    private func handleBinaryMessage(_ data: Data) {
        // 바이너리 메시지는 현재 사용하지 않음
        print("📥 Received binary data: \(data.count) bytes")
    }

    private func handleError(_ error: Error?) {
        print("❌ WebSocket error: \(error?.localizedDescription ?? "Unknown")")

        DispatchQueue.main.async {
            self.delegate?.webSocketDidDisconnect(error: error)
        }
    }

    // MARK: - Reconnection

    private func attemptReconnect() {
        reconnectTimer?.invalidate()

        reconnectAttempts += 1
        print("🔄 Attempting reconnect (\(reconnectAttempts)/\(maxReconnectAttempts))...")

        reconnectTimer = Timer.scheduledTimer(withTimeInterval: reconnectDelay, repeats: false) { [weak self] _ in
            self?.socket?.connect()
        }
    }
}

import Foundation

actor DouyinDanmakuClient {
    private static let endpoint = "wss://webcast5-ws-web-lf.douyin.com/webcast/im/push/v2/"
    private static let heartbeatInterval: Duration = .seconds(10)
    private static let batchInterval: Duration = .milliseconds(50)
    private static let logger = AppLogger(category: "DouyinDanmakuClient")

    private let api: DouyinAPI
    private var pending: [DanmakuMessage] = []
    private var pendingAudience: Int?
    private var lastAudience: Int?

    init(api: DouyinAPI) {
        self.api = api
    }

    nonisolated func events(roomID: String) -> AsyncStream<RoomEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: RoomEvent.self)
        let task = Task { await run(roomID: roomID, continuation: continuation) }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    private func run(roomID: String, continuation: AsyncStream<RoomEvent>.Continuation) async {
        var retryDelay: Duration = .seconds(1)
        while !Task.isCancelled {
            do {
                let socket = URLSession.shared.webSocketTask(with: try await handshake(roomID: roomID))
                socket.resume()
                defer { socket.cancel(with: .goingAway, reason: nil) }
                try await socket.send(.data(Self.frame(type: "hb")))
                retryDelay = .seconds(1)
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask { try await self.receive(socket) }
                    group.addTask { try await self.heartbeat(socket) }
                    group.addTask { try await self.flush(into: continuation) }
                    try await group.next()
                    group.cancelAll()
                }
            } catch is CancellationError {
            } catch {
                Self.logger.error("弹幕连接中断：\(error.localizedDescription)")
            }
            pending.removeAll()
            pendingAudience = nil
            lastAudience = nil
            guard !Task.isCancelled else { break }
            do { try await Task.sleep(for: retryDelay) } catch { break }
            retryDelay = min(retryDelay * 2, .seconds(10))
        }
        continuation.finish()
    }

    private func handshake(roomID: String) async throws(LiveError) -> URLRequest {
        let userAgent = DouyinAPI.userAgent
        let uniqueID = String((0..<12).map { _ in Character(String(Int.random(in: 0..<10))) })
        let signature = try DouyinSigner.socketSignature(roomID: roomID, uniqueID: uniqueID, userAgent: userAgent)
        let parameters: [(String, String)] = [
            ("app_name", "douyin_web"), ("version_code", "180800"), ("webcast_sdk_version", "1.3.0"),
            ("update_version_code", "1.3.0"), ("compress", "gzip"),
            ("cursor", "h-1_t-\(Int(Date.now.timeIntervalSince1970 * 1000))_r-1_d-1_u-1"),
            ("host", "https://live.douyin.com"), ("aid", "6383"), ("live_id", "1"), ("did_rule", "3"),
            ("debug", "false"), ("maxCacheMessageNumber", "20"), ("endpoint", "live_pc"), ("support_wrds", "1"),
            ("im_path", "/webcast/im/fetch/"), ("user_unique_id", uniqueID), ("device_platform", "web"),
            ("cookie_enabled", "true"), ("screen_width", "1920"), ("screen_height", "1080"),
            ("browser_language", "zh-CN"), ("browser_platform", "Win32"), ("browser_name", "Mozilla"),
            ("browser_version", userAgent.replacingOccurrences(of: "Mozilla/", with: "")),
            ("browser_online", "true"), ("tz_name", "Asia/Shanghai"), ("identity", "audience"),
            ("room_id", roomID), ("heartbeatDuration", "0"),
        ]
        let query = parameters.map { "\($0.0)=\(Self.encode($0.1))" }.joined(separator: "&")
        guard let url = URL(string: "\(Self.endpoint)?\(query)&signature=\(signature)") else {
            throw .badResponse("弹幕地址无效")
        }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("ttwid=\(try await api.ttwid())", forHTTPHeaderField: "Cookie")
        request.setValue("https://live.douyin.com", forHTTPHeaderField: "Origin")
        return request
    }

    private func heartbeat(_ socket: URLSessionWebSocketTask) async throws {
        while true {
            try await Task.sleep(for: Self.heartbeatInterval)
            try await socket.send(.data(Self.frame(type: "hb")))
        }
    }

    private func receive(_ socket: URLSessionWebSocketTask) async throws {
        while true {
            guard case .data(let data) = try await socket.receive() else { continue }
            guard let frame = ProtobufMessage(data), let payload = frame.bytes(8),
                let inflated = GzipPayload.inflate(payload), let response = ProtobufMessage(inflated)
            else { continue }
            if response.varint(9) == 1 {
                try await socket.send(
                    .data(Self.frame(type: "ack", logID: frame.varint(2), payload: response.bytes(5))))
            }
            for raw in response.repeatedBytes(1) {
                guard let message = ProtobufMessage(raw), let body = message.message(2) else { continue }
                switch message.string(1) {
                case "WebcastChatMessage":
                    guard let content = body.string(3), !content.isEmpty else { continue }
                    pending.append(DanmakuMessage(userName: body.message(2)?.string(3) ?? "", text: content))
                case "WebcastRoomUserSeqMessage":
                    guard let total = body.varint(3), Int(total) != lastAudience else { continue }
                    lastAudience = Int(total)
                    pendingAudience = Int(total)
                default:
                    break
                }
            }
        }
    }

    private func flush(into continuation: AsyncStream<RoomEvent>.Continuation) async throws {
        while true {
            try await Task.sleep(for: Self.batchInterval)
            if let count = pendingAudience {
                continuation.yield(.audienceCount(count))
                pendingAudience = nil
            }
            guard !pending.isEmpty else { continue }
            continuation.yield(.danmaku(pending))
            pending.removeAll(keepingCapacity: true)
        }
    }

    private static func frame(type: String, logID: UInt64? = nil, payload: Data? = nil) -> Data {
        var writer = ProtobufWriter()
        if let logID { writer.write(2, varint: logID) }
        writer.write(7, string: type)
        if let payload { writer.write(8, bytes: payload) }
        return writer.data
    }

    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}

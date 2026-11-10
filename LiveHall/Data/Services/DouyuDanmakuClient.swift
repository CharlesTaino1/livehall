import Foundation

actor DouyuDanmakuClient {
    private static let endpoint = URL(string: "wss://danmuproxy.douyu.com:8506/")!
    private static let heartbeatInterval: Duration = .seconds(45)
    private static let batchInterval: Duration = .milliseconds(50)
    private static let logger = AppLogger(category: "DouyuDanmakuClient")

    private var pending: [DanmakuMessage] = []
    private var pendingAudience: Int?
    private var lastAudience: Int?

    nonisolated func events(roomID: Int) -> AsyncStream<RoomEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: RoomEvent.self)
        let task = Task { await run(roomID: roomID, continuation: continuation) }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    private func run(roomID: Int, continuation: AsyncStream<RoomEvent>.Continuation) async {
        var retryDelay: Duration = .seconds(1)
        while !Task.isCancelled {
            let socket = URLSession.shared.webSocketTask(with: Self.endpoint)
            socket.resume()
            do {
                try await join(socket, roomID: roomID)
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
            socket.cancel(with: .goingAway, reason: nil)
            pending.removeAll()
            pendingAudience = nil
            lastAudience = nil
            guard !Task.isCancelled else { break }
            do { try await Task.sleep(for: retryDelay) } catch { break }
            retryDelay = min(retryDelay * 2, .seconds(10))
        }
        continuation.finish()
    }

    private func join(_ socket: URLSessionWebSocketTask, roomID: Int) async throws {
        try await socket.send(.data(DouyuSTT.pack([("type", "loginreq"), ("roomid", "\(roomID)")])))
        try await socket.send(.data(DouyuSTT.pack([("type", "joingroup"), ("rid", "\(roomID)"), ("gid", "-9999")])))
    }

    private func heartbeat(_ socket: URLSessionWebSocketTask) async throws {
        while true {
            try await Task.sleep(for: Self.heartbeatInterval)
            try await socket.send(.data(DouyuSTT.pack([("type", "mrkl")])))
        }
    }

    private func receive(_ socket: URLSessionWebSocketTask) async throws {
        while true {
            guard case .data(let data) = try await socket.receive() else { continue }
            for body in DouyuSTT.unpack(data) {
                if body.hasPrefix("type@=chatmsg/") {
                    let fields = DouyuSTT.parse(body)
                    guard let text = fields["txt"], !text.isEmpty else { continue }
                    pending.append(DanmakuMessage(userName: fields["nn"] ?? "", text: text))
                } else if body.hasPrefix("type@=oni/") {
                    guard let count = DouyuSTT.parse(body)["vn"].flatMap({ Int($0) }), count != lastAudience else {
                        continue
                    }
                    lastAudience = count
                    pendingAudience = count
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
}

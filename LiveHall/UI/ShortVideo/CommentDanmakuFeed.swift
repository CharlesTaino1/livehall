import Observation

@MainActor
@Observable
final class CommentDanmakuFeed {
    private static let maxTextLength = 40

    let channel = DanmakuChannel()
    var isEnabled = true {
        didSet { if !isEnabled { channel.clear() } }
    }

    @ObservationIgnored var isPlaying = true
    @ObservationIgnored private let settings: PlaybackSettings
    @ObservationIgnored private var source: CommentsViewModel?
    @ObservationIgnored private var cursor = 0
    @ObservationIgnored private var task: Task<Void, Never>?

    init(settings: PlaybackSettings) {
        self.settings = settings
    }

    func follow(_ comments: CommentsViewModel?) {
        source = comments
        cursor = 0
        channel.clear()
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.interval else { return }
                do { try await Task.sleep(for: interval) } catch { return }
                self?.emitNext()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        source = nil
        channel.clear()
    }

    private var interval: Duration {
        switch settings.danmaku.density {
        case .sparse: .milliseconds(1600)
        case .normal: .milliseconds(1000)
        case .dense: .milliseconds(600)
        }
    }

    private func emitNext() {
        guard isEnabled, isPlaying, let source, !source.comments.isEmpty else { return }
        if source.hasMore, cursor >= source.comments.count - 5 {
            Task { await source.loadMore() }
        }
        if cursor >= source.comments.count {
            if source.hasMore { return }
            cursor = 0
        }
        let settings = settings.danmaku
        for _ in 0..<5 {
            guard cursor < source.comments.count else { return }
            let comment = source.comments[cursor]
            cursor += 1
            let text = Self.plain(comment.text)
            guard !text.isEmpty, text.count <= Self.maxTextLength, !settings.isBlocked(text) else { continue }
            channel.send([DanmakuMessage(userName: comment.authorName, text: text)])
            return
        }
    }

    private static func plain(_ text: String) -> String {
        text.replacing(/\[[^\]\s]{1,8}\]/, with: "")
            .replacing(/\s+/, with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}

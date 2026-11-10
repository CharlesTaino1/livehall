@MainActor
final class DanmakuChannel {
    var onSubmit: (([DanmakuMessage]) -> Void)?
    var onClear: (() -> Void)?

    func send(_ messages: [DanmakuMessage]) { onSubmit?(messages) }

    func clear() { onClear?() }
}

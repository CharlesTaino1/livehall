enum RoomEvent: Sendable, Equatable {
    case danmaku([DanmakuMessage])
    case audienceCount(Int)
}

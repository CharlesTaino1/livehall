struct StreamPreference: Sendable, Equatable, Codable {
    var rate = -1
    var cdn = ""
}

struct Preferences: Sendable, Equatable, Codable {
    var danmaku = DanmakuSettings()
    var stream = StreamPreference()
    var douyinStream: StreamPreference?
    var volume = 1.0
    var isMuted = false
    var page = Page()
    var multiView: MultiViewState?
    var miniPlayerWidth: Double?
    var shortVideoAutoNext: Bool?
    var shortVideoDanmaku: Bool?

    func streamPreference(for platform: Platform) -> StreamPreference {
        switch platform {
        case .douyu: stream
        case .douyin: douyinStream ?? StreamPreference()
        }
    }

    mutating func setStreamPreference(_ preference: StreamPreference, for platform: Platform) {
        switch platform {
        case .douyu: stream = preference
        case .douyin: douyinStream = preference
        }
    }
}

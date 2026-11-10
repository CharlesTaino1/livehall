import Foundation

actor LocalStore {
    private static let recentLimit = 50

    private static let logger = AppLogger(category: "LocalStore")

    nonisolated let launchPage: Page
    nonisolated let launchMultiView: MultiViewState
    nonisolated let launchMiniPlayerWidth: Double?

    private let libraryURL: URL
    private let preferencesURL: URL
    private let sessionURL: URL
    private let douyinSessionURL: URL
    private var library: Library?
    private var preferences: Preferences
    private var session: DouyuSession?
    private var isSessionLoaded = false
    private var douyinSession: DouyinSession?
    private var isDouyinSessionLoaded = false

    init() {
        let base = URL.applicationSupportDirectory.appending(path: "LiveHall", directoryHint: .isDirectory)
        libraryURL = base.appending(path: "library.json")
        preferencesURL = base.appending(path: "preferences.json")
        sessionURL = base.appending(path: "session.json")
        douyinSessionURL = base.appending(path: "douyin-session.json")
        let loaded = Self.read(Preferences.self, from: preferencesURL) ?? Preferences()
        preferences = loaded
        launchPage = loaded.page
        launchMultiView = loaded.multiView ?? MultiViewState()
        launchMiniPlayerWidth = loaded.miniPlayerWidth
    }

    func current() -> Library {
        if let library { return library }
        let loaded = Self.read(Library.self, from: libraryURL) ?? Library()
        library = loaded
        return loaded
    }

    func currentPreferences() -> Preferences {
        preferences
    }

    func updatePreferences(_ change: @Sendable (inout Preferences) -> Void) {
        var updated = preferences
        change(&updated)
        guard updated != preferences else { return }
        preferences = updated
        write(updated, to: preferencesURL)
    }

    func currentSession() -> DouyuSession? {
        if !isSessionLoaded {
            session = Self.read(DouyuSession.self, from: sessionURL)
            isSessionLoaded = true
        }
        return session
    }

    func saveSession(_ newSession: DouyuSession?) {
        session = newSession
        isSessionLoaded = true
        if let newSession {
            write(newSession, to: sessionURL)
        } else {
            remove(sessionURL)
        }
    }

    func currentDouyinSession() -> DouyinSession? {
        if !isDouyinSessionLoaded {
            douyinSession = Self.read(DouyinSession.self, from: douyinSessionURL)
            isDouyinSessionLoaded = true
        }
        return douyinSession
    }

    func saveDouyinSession(_ newSession: DouyinSession?) {
        douyinSession = newSession
        isDouyinSessionLoaded = true
        if let newSession {
            write(newSession, to: douyinSessionURL)
        } else {
            remove(douyinSessionURL)
        }
    }

    func follow(_ anchor: FollowedAnchor) {
        update { library in
            guard !library.isFollowing(anchor.roomID) else { return }
            library.follows.insert(anchor, at: 0)
        }
    }

    func unfollow(roomID: RoomID) {
        update { $0.follows.removeAll { $0.roomID == roomID } }
    }

    func markWatched(roomID: RoomID, at date: Date) {
        update { library in
            library.recents.removeAll { $0.roomID == roomID }
            library.recents.insert(WatchRecord(roomID: roomID, watchedAt: date), at: 0)
            if library.recents.count > Self.recentLimit {
                library.recents.removeLast(library.recents.count - Self.recentLimit)
            }
        }
    }

    private func update(_ change: (inout Library) -> Void) {
        var updated = current()
        change(&updated)
        guard updated != library else { return }
        library = updated
        write(updated, to: libraryURL)
    }

    private static func read<Value: Decodable>(_ type: Value.Type, from url: URL) -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try Self.decoder.decode(type, from: data)
        } catch {
            Self.logger.error("本机数据无法解析，按空数据处理：\(error.localizedDescription)")
            return nil
        }
    }

    private func remove(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
        } catch {
            Self.logger.error("登录会话删除失败：\(error.localizedDescription)")
        }
    }

    private func write<Value: Encodable>(_ value: Value, to url: URL) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.encoder.encode(value).write(to: url, options: .atomic)
        } catch {
            Self.logger.error("本机数据写入失败：\(error.localizedDescription)")
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

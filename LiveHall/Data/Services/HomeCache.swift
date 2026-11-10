import Foundation

struct HomeCache: Sendable {
    private static let maxAge: TimeInterval = 24 * 60 * 60

    private let fileURL = URL.cachesDirectory.appending(path: "LiveHall/home.json")
    private let logger = AppLogger(category: "HomeCache")

    func load() async -> HomeSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            let snapshot = try Self.decoder.decode(HomeSnapshot.self, from: data)
            return Date.now.timeIntervalSince(snapshot.savedAt) < Self.maxAge ? snapshot : nil
        } catch {
            logger.error("首页缓存无法解析：\(error.localizedDescription)")
            return nil
        }
    }

    func save(_ snapshot: HomeSnapshot) async {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.encoder.encode(snapshot).write(to: fileURL, options: .atomic)
        } catch {
            logger.error("首页缓存写入失败：\(error.localizedDescription)")
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

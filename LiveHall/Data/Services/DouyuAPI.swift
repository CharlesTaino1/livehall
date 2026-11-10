import Foundation

struct DouyuAPI: Sendable {
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) "
        + "Chrome/130.0.0.0 Safari/537.36"
    private static let deviceID = "10000000000000000000000000001501"
    private static let anonymousRates: Set<Int> = [4, 3, 2]
    private static let playParameters = "&ver=Douyu_223061205&iar=0&ive=0&hevc=0&fa=0"

    private static let logger = AppLogger(category: "DouyuAPI")

    private let http: HTTPClient

    init(http: HTTPClient) {
        self.http = http
    }

    func room(id: Int) async throws(LiveError) -> LiveRoom {
        let room = try await roomInfo(id: id)
        return LiveRoom(
            id: RoomID(.douyu, room.roomID),
            connectionID: String(room.roomID),
            anchorName: room.nickname,
            avatarURL: room.avatar.flatMap { URL(string: $0.middle) },
            title: room.roomName,
            isLive: room.isLive,
            categoryName: room.categoryName ?? "",
            popularity: room.biz?.hot.flatMap { Int($0) } ?? 0,
            startedAt: room.isLive ? room.showTime.map { Date(timeIntervalSince1970: TimeInterval($0)) } : nil,
            clubName: room.biz?.clubName.flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    func ranking(roomID: Int) async throws(LiveError) -> RoomRanking? {
        let data = try await fetch(
            request(
                url: "https://www.douyu.com/japi/creator/w/anchorRank2505/entry?rid=\(roomID)",
                referer: "https://www.douyu.com/\(roomID)"))
        let envelope: RankingEnvelope
        do {
            envelope = try JSONDecoder().decode(RankingEnvelope.self, from: data)
        } catch {
            throw .badResponse("榜单应答无法解析")
        }
        guard let entry = envelope.data?.anchorInfoList?.first, entry.idx > 0 else { return nil }
        return RoomRanking(name: entry.name, position: entry.idx)
    }

    func recommendations() async throws(LiveError) -> [RoomSummary] {
        try await roomList(path: "/gapi/rkc/directory/mixList/0_0/1").rooms
    }

    func rooms(categoryID: Int, page: Int) async throws(LiveError) -> RoomPage {
        try await roomList(path: "/gapi/rkc/directory/mixList/2_\(categoryID)/\(page)")
    }

    func categoryGroups() async throws(LiveError) -> [CategoryGroup] {
        let data = try await fetch(request(url: "https://m.douyu.com/api/cate/list", referer: "https://m.douyu.com/"))
        let envelope: CategoryEnvelope
        do {
            envelope = try JSONDecoder().decode(CategoryEnvelope.self, from: data)
        } catch {
            throw .badResponse("分区应答无法解析")
        }
        return envelope.data.cate1Info.compactMap { group in
            let categories = envelope.data.cate2Info
                .filter { $0.cate1Id == group.cate1Id && $0.isVertical == 0 }
                .map {
                    LiveCategory(
                        name: $0.cate2Name, sources: [.init(platform: .douyu, id: $0.cate2Id)],
                        liveCount: $0.count, posterURL: URL(string: $0.pic))
                }
                .sorted { ($0.liveCount ?? 0) > ($1.liveCount ?? 0) }
            guard !categories.isEmpty else { return nil }
            return CategoryGroup(name: group.cate1Name, categories: categories)
        }
    }

    func summaries(roomIDs: [Int]) async throws(LiveError) -> [RoomSummary] {
        try await RoomLookup.summaries(of: roomIDs) { await self.summary(roomID: $0) }
    }

    private func summary(roomID: Int) async -> Result<RoomSummary, LiveError> {
        do throws(LiveError) {
            let room = try await roomInfo(id: roomID)
            return .success(
                RoomSummary(
                    id: RoomID(.douyu, room.roomID),
                    anchorName: room.nickname,
                    title: room.roomName,
                    categoryName: room.categoryName ?? "",
                    popularity: room.biz?.hot.flatMap { Int($0) } ?? 0,
                    coverURL: room.coverPath.flatMap(Self.listCoverURL),
                    avatarURL: room.avatar.flatMap { URL(string: $0.middle) },
                    isLive: room.isLive
                ))
        } catch {
            return .failure(error)
        }
    }

    private func roomInfo(id: Int) async throws(LiveError) -> RoomEnvelope.Room {
        let data = try await fetch(request(path: "/betard/\(id)", roomID: id))
        do {
            return try JSONDecoder().decode(RoomEnvelope.self, from: data).room
        } catch {
            throw .roomNotFound
        }
    }

    private static func listCoverURL(_ path: String) -> URL? {
        URL(string: path)?.deletingLastPathComponent().appending(path: "dy1")
    }

    private func roomList(path: String) async throws(LiveError) -> RoomPage {
        let data = try await fetch(request(url: "https://www.douyu.com\(path)", referer: "https://www.douyu.com/"))
        let envelope: RoomListEnvelope
        do {
            envelope = try JSONDecoder().decode(RoomListEnvelope.self, from: data)
        } catch {
            throw .badResponse("列表应答无法解析")
        }
        let rooms = envelope.data.rl.filter { $0.type == 1 && $0.rst != 3 }.map { item in
            RoomSummary(
                id: RoomID(.douyu, item.rid),
                anchorName: item.nn,
                title: item.rn,
                categoryName: item.c2name,
                popularity: item.ol,
                coverURL: URL(string: item.rs16),
                avatarURL: URL(string: "https://apic.douyucdn.cn/upload/\(item.av)_middle.jpg"),
                isLive: true
            )
        }
        return RoomPage(rooms: rooms, pageCount: envelope.data.pgcnt)
    }

    func stream(roomID: Int, rate: Int, cdn: String, session: DouyuSession?) async throws(LiveError) -> LiveStream {
        let script = try await encryptionScript(roomID: roomID, session: session)
        let timestamp = Int(Date.now.timeIntervalSince1970)
        let signed = try DouyuSigner.sign(
            script: script, roomID: roomID, deviceID: session?.deviceID ?? Self.deviceID, timestamp: timestamp)

        var play = request(path: "/lapi/live/getH5Play/\(roomID)", roomID: roomID, session: session)
        play.httpMethod = "POST"
        play.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        play.httpBody = Data("\(signed)&cdn=\(cdn)&rate=\(rate)\(Self.playParameters)".utf8)
        let data = try await fetch(play)

        let status: PlayStatus
        do {
            status = try JSONDecoder().decode(PlayStatus.self, from: data)
        } catch {
            throw .badResponse("取流应答无法解析")
        }
        switch status.error {
        case 0: break
        case 102: throw .roomNotFound
        case -5, 104: throw .notLive
        default: throw .badResponse(status.msg)
        }

        let play2: PlayEnvelope
        do {
            play2 = try JSONDecoder().decode(PlayEnvelope.self, from: data)
        } catch {
            throw .badResponse("取流应答缺少字段")
        }
        let info = play2.data
        guard let url = URL(string: "\(info.rtmpURL)/\(info.rtmpLive)") else { throw .badResponse("流地址无效") }
        var streamRequest = URLRequest(url: url)
        streamRequest.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        streamRequest.setValue("https://www.douyu.com/\(roomID)", forHTTPHeaderField: "Referer")
        let requested = "rate \(rate) cdn \(cdn.isEmpty ? "自动" : cdn)"
        let actual = "rate \(info.rate) cdn \(info.rtmpCDN)"
        Self.logger.info(
            "取流 房间 \(roomID)，请求 \(requested)，实际 \(actual)，登录 \(session == nil ? "否" : "是")，可选档位 \(info.multirates.map(\.rate))"
        )
        return LiveStream(
            request: streamRequest,
            qualities: Self.qualities(info.multirates, isSignedIn: session != nil),
            lines: info.cdnsWithName.map { StreamLine(cdn: $0.cdn, name: $0.name) },
            currentRate: info.rate,
            currentCDN: info.rtmpCDN
        )
    }

    private static func qualities(_ rates: [PlayEnvelope.Rate], isSignedIn: Bool) -> [StreamQuality] {
        let usable = isSignedIn ? rates : rates.filter { anonymousRates.contains($0.rate) }
        return (usable.isEmpty ? rates : usable).map { StreamQuality(rate: $0.rate, name: $0.name) }
    }

    private func encryptionScript(roomID: Int, session: DouyuSession?) async throws(LiveError) -> String {
        let data = try await fetch(
            request(path: "/swf_api/homeH5Enc?rids=\(roomID)", roomID: roomID, session: session))
        let envelope: ScriptEnvelope
        do {
            envelope = try JSONDecoder().decode(ScriptEnvelope.self, from: data)
        } catch {
            throw .badResponse("签名脚本应答无法解析")
        }
        guard envelope.error == 0, let script = envelope.data["room\(roomID)"] else {
            throw .badResponse("没有拿到签名脚本")
        }
        return script
    }

    private func request(path: String, roomID: Int, session: DouyuSession? = nil) -> URLRequest {
        request(url: "https://www.douyu.com\(path)", referer: "https://www.douyu.com/\(roomID)", session: session)
    }

    private func request(url: String, referer: String, session: DouyuSession? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: url)!)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        if let session {
            request.httpShouldHandleCookies = false
            request.setValue(session.cookieHeader, forHTTPHeaderField: "Cookie")
        }
        return request
    }

    private func fetch(_ request: URLRequest) async throws(LiveError) -> Data {
        try await http.data(for: request)
    }
}

private struct RoomEnvelope: Decodable {
    struct Room: Decodable {
        let roomID: Int
        let roomName: String
        let nickname: String
        let showStatus: Int
        let videoLoop: Int?
        let avatar: Avatar?
        let categoryName: String?
        let showTime: Int?
        let coverPath: String?
        let biz: Biz?

        var isLive: Bool { showStatus == 1 && videoLoop != 1 }

        struct Avatar: Decodable {
            let middle: String
        }

        struct Biz: Decodable {
            let hot: String?
            let clubName: String?

            enum CodingKeys: String, CodingKey {
                case hot
                case clubName = "clubOrgName"
            }
        }

        enum CodingKeys: String, CodingKey {
            case roomID = "room_id"
            case roomName = "room_name"
            case nickname
            case avatar
            case showStatus = "show_status"
            case videoLoop
            case categoryName = "second_lvl_name"
            case showTime = "show_time"
            case coverPath = "room_pic"
            case biz = "room_biz_all"
        }
    }
    let room: Room
}

private struct RankingEnvelope: Decodable {
    struct Payload: Decodable {
        struct Entry: Decodable {
            let name: String
            let idx: Int
        }
        let anchorInfoList: [Entry]?
    }
    let data: Payload?
}

private struct ScriptEnvelope: Decodable {
    let error: Int
    let data: [String: String]
}

private struct PlayStatus: Decodable {
    let error: Int
    let msg: String
}

private struct PlayEnvelope: Decodable {
    struct Rate: Decodable {
        let name: String
        let rate: Int
    }
    struct Line: Decodable {
        let name: String
        let cdn: String
    }
    struct Info: Decodable {
        let rtmpURL: String
        let rtmpLive: String
        let rtmpCDN: String
        let rate: Int
        let multirates: [Rate]
        let cdnsWithName: [Line]

        enum CodingKeys: String, CodingKey {
            case rtmpURL = "rtmp_url"
            case rtmpLive = "rtmp_live"
            case rtmpCDN = "rtmp_cdn"
            case rate
            case multirates
            case cdnsWithName
        }
    }
    let data: Info
}

private struct RoomListEnvelope: Decodable {
    struct Item: Decodable {
        let type: Int
        let rid: Int
        let rn: String
        let nn: String
        let ol: Int
        let av: String
        let rs16: String
        let c2name: String
        let rst: Int?
    }
    struct Page: Decodable {
        let rl: [Item]
        let pgcnt: Int
    }
    let data: Page
}

private struct CategoryEnvelope: Decodable {
    struct Group: Decodable {
        let cate1Id: Int
        let cate1Name: String
    }
    struct Category: Decodable {
        let cate1Id: Int
        let cate2Id: Int
        let cate2Name: String
        let count: Int
        let isVertical: Int
        let pic: String
    }
    struct Payload: Decodable {
        let cate1Info: [Group]
        let cate2Info: [Category]
    }
    let data: Payload
}

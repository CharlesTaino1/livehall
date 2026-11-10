import Foundation

struct DouyinAPI: Sendable {
    static let userAgent =
        "Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.5845.97 "
        + "Safari/537.36 Core/1.116.567.400 QQBrowser/19.7.6764.400"

    static let videoHeaders = ["Referer": "https://www.douyin.com/"]

    private static let host = "https://live.douyin.com"
    private static let webHost = "https://www.douyin.com"
    private static let feedBatchCount = 3
    private static let commentPageSize = 20
    private static let recommendPartition = (id: 720, kind: 1)
    private static let pageSize = 15
    private static let gamesGroupID = 103
    private static let streamKeys: [(key: String, rate: Int, name: String)] = [
        ("origin", 5, "原画"), ("uhd", 4, "蓝光"), ("hd", 3, "超清"), ("sd", 2, "高清"), ("ld", 1, "标清"),
        ("md", 0, "流畅"),
    ]
    private static let logger = AppLogger(category: "DouyinAPI")

    private static let webQuery =
        "device_platform=webapp&aid=6383&channel=channel_pc_web&version_code=170400&version_name=17.4.0"
        + "&cookie_enabled=true&screen_width=1920&screen_height=1080&browser_language=zh-CN"
        + "&browser_platform=Win32&browser_name=Chrome&browser_version=116.0.0.0&browser_online=true"
        + "&engine_name=Blink&os_name=Windows&os_version=10&cpu_core_num=8&device_memory=8&platform=PC"

    private let http: HTTPClient
    private let account: AccountRepository
    private let identity = DouyinIdentity()

    init(http: HTTPClient, account: AccountRepository) {
        self.http = http
        self.account = account
    }

    func ttwid() async throws(LiveError) -> String {
        try await identity.ttwid(using: http)
    }

    func room(webRid: Int) async throws(LiveError) -> LiveRoom {
        let (room, user) = try await enter(webRid: webRid)
        let owner = room.owner
        return LiveRoom(
            id: RoomID(.douyin, webRid),
            connectionID: room.roomID,
            anchorName: owner?.nickname ?? user?.nickname ?? "",
            avatarURL: (owner?.avatarThumb ?? user?.avatarThumb)?.url,
            title: room.title ?? "",
            isLive: room.status == 2,
            categoryName: room.gameData?.tag?.name ?? "",
            popularity: room.popularity,
            startedAt: nil,
            clubName: nil
        )
    }

    func recommendations() async throws(LiveError) -> [RoomSummary] {
        try await roomList(
            partition: Self.recommendPartition.id, kind: Self.recommendPartition.kind, categoryName: "", page: 1
        ).rooms
    }

    func rooms(source: LiveCategory.Source, categoryName: String, page: Int) async throws(LiveError) -> RoomPage {
        try await roomList(partition: source.id, kind: source.kind, categoryName: categoryName, page: page)
    }

    func categoryGroups() async throws(LiveError) -> [CategoryGroup] {
        let html = try await fetch(request(url: "\(Self.host)/", referer: "\(Self.host)/"))
        let entries = try DouyinCategoryPage.entries(in: html)
        let groups = entries.map { entry in
            func category(_ item: DouyinCategoryPage.Entry, named name: String) -> LiveCategory {
                LiveCategory(
                    name: name, sources: [.init(platform: .douyin, id: item.id, kind: item.kind)], liveCount: nil,
                    posterURL: nil)
            }
            let subs = entry.subs.map { category($0, named: $0.title) }
            if entry.id == Self.gamesGroupID, !subs.isEmpty {
                return (entry.id, CategoryGroup(name: entry.title, categories: [category(entry, named: "全部游戏")] + subs))
            }
            return (entry.id, CategoryGroup(name: entry.title, categories: [category(entry, named: entry.title)]))
        }
        return groups.filter { $0.0 == Self.gamesGroupID }.map(\.1)
            + groups.filter { $0.0 != Self.gamesGroupID }.map(\.1)
    }

    func summaries(webRids: [Int]) async throws(LiveError) -> [RoomSummary] {
        try await RoomLookup.summaries(of: webRids) { await self.summary(webRid: $0) }
    }

    func feed() async throws(LiveError) -> [ShortVideo] {
        let batches = try await PlatformMerge.gather(count: Self.feedBatchCount) { _ throws(LiveError) in
            try await self.feedBatch()
        }
        var seen: Set<String> = []
        return batches.flatMap { $0 }.filter { seen.insert($0.id).inserted }
    }

    func comments(videoID: String, cursor: Int) async throws(LiveError) -> CommentPage {
        let url = try DouyinSigner.signedURL(
            "\(Self.webHost)/aweme/v1/web/comment/list/?\(Self.webQuery)&aweme_id=\(videoID)&cursor=\(cursor)"
                + "&count=\(Self.commentPageSize)&item_type=0",
            userAgent: Self.userAgent)
        let data = try await fetch(try await request(url: url, referer: "\(Self.webHost)/"))
        let envelope: DouyinCommentEnvelope
        do {
            envelope = try JSONDecoder().decode(DouyinCommentEnvelope.self, from: data)
        } catch {
            throw .badResponse("评论应答无法解析")
        }
        let comments = (envelope.comments ?? []).compactMap { item -> VideoComment? in
            guard let text = item.text, !text.isEmpty else { return nil }
            return VideoComment(
                id: item.id,
                text: text,
                authorName: item.user?.nickname ?? "",
                avatarURL: item.user?.avatarThumb?.url,
                likeCount: item.likeCount ?? 0,
                replyCount: item.replyCount ?? 0,
                createdAt: item.createTime.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                region: item.region ?? "")
        }
        return CommentPage(
            comments: comments, nextCursor: envelope.hasMore == 1 ? envelope.cursor : nil,
            total: envelope.total ?? 0)
    }

    func stream(webRid: Int, rate: Int, line: String) async throws(LiveError) -> LiveStream {
        let (room, _) = try await enter(webRid: webRid)
        guard room.status == 2 else { throw .notLive }
        guard let pull = room.streamURL?.coreData?.pullData, let text = pull.streamData,
            let streams = try? JSONDecoder().decode(DouyinStreamData.self, from: Data(text.utf8))
        else { throw .badResponse("取流应答缺少流数据") }

        let names = Dictionary(
            (pull.options?.qualities ?? []).map { ($0.key, $0.name) }, uniquingKeysWith: { first, _ in first })
        let available = Self.streamKeys.filter { streams.data[$0.key]?.main?.flv != nil }
        guard !available.isEmpty else { throw .badResponse("没有可用的清晰度") }
        let defaultRate = available.first { $0.key == pull.options?.defaultQuality?.key }?.rate
        let wanted = rate >= 0 ? rate : (defaultRate ?? available[0].rate)
        let chosen = available.first { $0.rate <= wanted } ?? available[available.count - 1]
        guard let entry = streams.data[chosen.key] else { throw .badResponse("清晰度缺少流地址") }

        let useBackup = line == "backup" && entry.backup?.flv != nil
        guard let flv = (useBackup ? entry.backup?.flv : entry.main?.flv), let url = URL(string: flv) else {
            throw .badResponse("流地址无效")
        }
        var streamRequest = URLRequest(url: url)
        streamRequest.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let hasBackup = streams.data.values.contains { $0.backup?.flv != nil }
        Self.logger.info(
            "取流 房间 \(webRid)，请求 rate \(rate) 线路 \(line.isEmpty ? "自动" : line)，实际 \(chosen.key) \(useBackup ? "备线" : "主线")，可选档位 \(available.map(\.key))"
        )
        return LiveStream(
            request: streamRequest,
            qualities: available.map { StreamQuality(rate: $0.rate, name: names[$0.key] ?? $0.name) },
            lines: hasBackup ? [StreamLine(cdn: "main", name: "线路1"), StreamLine(cdn: "backup", name: "线路2")] : [],
            currentRate: chosen.rate,
            currentCDN: useBackup ? "backup" : "main"
        )
    }

    private func feedBatch() async throws(LiveError) -> [ShortVideo] {
        let session = await account.douyinSession()
        var query =
            "\(Self.webQuery)&count=10&refresh_index=1&video_type_select=1&aweme_pc_rec_raw_data=%7B%7D"
            + "&pull_type=1&tag_id="
        if let fingerprint = session?.verifyFingerprint { query += "&verifyFp=\(fingerprint)&fp=\(fingerprint)" }
        let url = try DouyinSigner.signedURL(
            "\(Self.webHost)/aweme/v1/web/tab/feed/?\(query)", userAgent: Self.userAgent)
        let data = try await fetch(try await request(url: url, referer: "\(Self.webHost)/", session: session))
        let envelope: DouyinFeedEnvelope
        do {
            envelope = try JSONDecoder().decode(DouyinFeedEnvelope.self, from: data)
        } catch {
            throw .badResponse("视频流应答无法解析")
        }
        return (envelope.awemeList ?? []).compactMap { item -> ShortVideo? in
            guard item.isAds != true, let video = item.video, let width = video.width, let height = video.height,
                width > 0, height > 0,
                let address = video.playAddress?.urlList.first(where: { $0.contains("/aweme/v1/play/") }),
                let playURL = URL(string: address)
            else { return nil }
            return ShortVideo(
                id: item.id,
                description: item.description ?? "",
                authorName: item.author?.nickname ?? "",
                avatarURL: item.author?.avatarThumb?.url,
                coverURL: video.cover?.url,
                playURL: playURL,
                aspectRatio: Double(width) / Double(height),
                likeCount: item.statistics?.diggCount ?? 0,
                commentCount: item.statistics?.commentCount ?? 0
            )
        }
    }

    private func summary(webRid: Int) async -> Result<RoomSummary, LiveError> {
        do throws(LiveError) {
            let (room, user) = try await enter(webRid: webRid)
            return .success(
                RoomSummary(
                    id: RoomID(.douyin, webRid),
                    anchorName: room.owner?.nickname ?? user?.nickname ?? "",
                    title: room.title ?? "",
                    categoryName: room.gameData?.tag?.name ?? "",
                    popularity: room.popularity,
                    coverURL: room.cover?.url,
                    avatarURL: (room.owner?.avatarThumb ?? user?.avatarThumb)?.url,
                    isLive: room.status == 2
                ))
        } catch {
            return .failure(error)
        }
    }

    private func enter(webRid: Int) async throws(LiveError) -> (DouyinRoom, DouyinEnterEnvelope.User?) {
        let query =
            "aid=6383&app_name=douyin_web&live_id=1&device_platform=web&language=zh-CN&browser_language=zh-CN"
            + "&browser_platform=Win32&browser_name=Chrome&browser_version=125.0.0.0&web_rid=\(webRid)"
        let url = try DouyinSigner.signedURL(
            "\(Self.host)/webcast/room/web/enter/?\(query)", userAgent: Self.userAgent)
        let data = try await fetch(try await request(url: url, referer: "\(Self.host)/\(webRid)"))
        let envelope: DouyinEnterEnvelope
        do {
            envelope = try JSONDecoder().decode(DouyinEnterEnvelope.self, from: data)
        } catch {
            throw .badResponse("房间应答无法解析")
        }
        guard let room = envelope.data.data.first else { throw .roomNotFound }
        return (room, envelope.data.user)
    }

    private func roomList(partition: Int, kind: Int, categoryName: String, page: Int) async throws(LiveError)
        -> RoomPage
    {
        let query =
            "aid=6383&app_name=douyin_web&live_id=1&device_platform=web&language=zh-CN&enter_from=link_share"
            + "&cookie_enabled=true&screen_width=1980&screen_height=1080&browser_language=zh-CN"
            + "&browser_platform=Win32&browser_name=Edge&browser_version=125.0.0.0&browser_online=true"
            + "&count=\(Self.pageSize)&offset=\((page - 1) * Self.pageSize)&partition=\(partition)"
            + "&partition_type=\(kind)&req_from=2"
        let url = try DouyinSigner.signedURL(
            "\(Self.host)/webcast/web/partition/detail/room/v2/?\(query)", userAgent: Self.userAgent)
        let data = try await fetch(try await request(url: url, referer: Self.host))
        let envelope: DouyinListEnvelope
        do {
            envelope = try JSONDecoder().decode(DouyinListEnvelope.self, from: data)
        } catch {
            throw .badResponse("列表应答无法解析")
        }
        let rooms = envelope.data.data.compactMap { item -> RoomSummary? in
            guard let number = Int(item.webRid), !item.room.isPortrait else { return nil }
            let room = item.room
            return RoomSummary(
                id: RoomID(.douyin, number),
                anchorName: room.owner?.nickname ?? "",
                title: room.title ?? "",
                categoryName: item.tagName.flatMap { $0.isEmpty ? nil : $0 } ?? categoryName,
                popularity: room.popularity,
                coverURL: room.cover?.url,
                avatarURL: room.owner?.avatarThumb?.url,
                isLive: true
            )
        }
        let hasMore = envelope.data.data.count >= Self.pageSize
        return RoomPage(rooms: rooms, pageCount: hasMore ? page + 1 : page)
    }

    private func request(url: String, referer: String) async throws(LiveError) -> URLRequest {
        guard let parsed = URL(string: url) else { throw .badResponse("地址无效") }
        return try await request(url: parsed, referer: referer)
    }

    private func request(url: URL, referer: String, session: DouyinSession? = nil) async throws(LiveError)
        -> URLRequest
    {
        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = false
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        var cookie = session?.cookieHeader ?? ""
        if session?.cookies["ttwid"] == nil {
            cookie += (cookie.isEmpty ? "" : "; ") + "ttwid=\(try await ttwid())"
        }
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        return request
    }

    private func fetch(_ request: URLRequest) async throws(LiveError) -> Data {
        try await http.data(for: request)
    }
}

private actor DouyinIdentity {
    private var cached: String?

    func ttwid(using http: HTTPClient) async throws(LiveError) -> String {
        if let cached { return cached }
        guard let home = URL(string: "https://live.douyin.com/") else { throw .badResponse("地址无效") }
        var request = URLRequest(url: home)
        request.httpShouldHandleCookies = false
        request.httpMethod = "HEAD"
        request.setValue(DouyinAPI.userAgent, forHTTPHeaderField: "User-Agent")
        let response = try await http.response(for: request)
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String { result[key] = value }
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: home)
        guard let value = cookies.first(where: { $0.name == "ttwid" })?.value else {
            throw .badResponse("没有拿到 ttwid")
        }
        cached = value
        return value
    }
}

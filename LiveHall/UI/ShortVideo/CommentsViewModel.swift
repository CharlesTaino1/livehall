import Observation

@MainActor
@Observable
final class CommentsViewModel {
    enum Phase {
        case loading
        case content
        case failed(offline: Bool)
    }

    let video: ShortVideo
    private(set) var phase = Phase.loading
    private(set) var comments: [VideoComment] = []
    private(set) var total = 0
    private(set) var hasMore = false
    private(set) var isLoadMoreFailed = false

    @ObservationIgnored private let repository: LiveRepository
    @ObservationIgnored private var cursor = 0
    @ObservationIgnored private var isLoadingMore = false
    @ObservationIgnored private let logger = AppLogger(category: "CommentsViewModel")

    init(video: ShortVideo, repository: LiveRepository) {
        self.video = video
        self.repository = repository
    }

    func load() async {
        phase = .loading
        do throws(LiveError) {
            let page = try await repository.comments(videoID: video.id, cursor: 0)
            guard !Task.isCancelled else { return }
            apply(page, replacing: true)
            phase = .content
        } catch {
            logger.error("评论加载失败：\(String(describing: error))")
            guard !Task.isCancelled else { return }
            phase = .failed(offline: error == .networkDown)
        }
    }

    func loadMore() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        isLoadMoreFailed = false
        defer { isLoadingMore = false }
        do throws(LiveError) {
            let page = try await repository.comments(videoID: video.id, cursor: cursor)
            guard !Task.isCancelled else { return }
            apply(page, replacing: false)
        } catch {
            logger.error("评论续取失败：\(String(describing: error))")
            guard !Task.isCancelled else { return }
            isLoadMoreFailed = true
        }
    }

    private func apply(_ page: CommentPage, replacing: Bool) {
        let known = replacing ? [] : Set(comments.map(\.id))
        let fresh = page.comments.filter { !known.contains($0.id) }
        comments = replacing ? fresh : comments + fresh
        total = page.total
        hasMore = page.nextCursor != nil
        cursor = page.nextCursor ?? cursor
    }
}

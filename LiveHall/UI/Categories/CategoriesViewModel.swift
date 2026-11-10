import Observation

@MainActor
@Observable
final class CategoriesViewModel {
    enum Phase {
        case loading
        case content([CategoryGroup])
        case failed(offline: Bool)
    }

    private(set) var phase = Phase.loading
    var selectedGroupID: String?

    @ObservationIgnored private let repository: LiveRepository
    @ObservationIgnored private let network: NetworkMonitor
    @ObservationIgnored private let logger = AppLogger(category: "CategoriesViewModel")

    init(repository: LiveRepository, network: NetworkMonitor) {
        self.repository = repository
        self.network = network
    }

    func loadIfNeeded() async {
        if case .content = phase { return }
        await load()
    }

    func load() async {
        phase = .loading
        do throws(LiveError) {
            let groups = try await repository.categoryGroups()
            guard !Task.isCancelled else { return }
            phase = .content(groups)
            if !groups.contains(where: { $0.id == selectedGroupID }) { selectedGroupID = groups.first?.id }
        } catch {
            logger.error("分区加载失败：\(String(describing: error))")
            guard !Task.isCancelled else { return }
            phase = .failed(offline: error == .networkDown)
        }
    }

    func refresh() async {
        guard case .content = phase else {
            await load()
            return
        }
        do throws(LiveError) {
            let groups = try await repository.categoryGroups()
            guard !Task.isCancelled else { return }
            phase = .content(groups)
            if !groups.contains(where: { $0.id == selectedGroupID }) { selectedGroupID = groups.first?.id }
        } catch {
            logger.error("分区刷新失败：\(String(describing: error))")
        }
    }

    func retryWhenOnline() async {
        for await isOnline in network.updates() where isOnline {
            if case .failed = phase { await load() }
        }
    }
}

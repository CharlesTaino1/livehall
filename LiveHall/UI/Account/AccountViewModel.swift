import Observation

@MainActor
@Observable
final class AccountViewModel {
    private(set) var session: DouyuSession?
    private(set) var douyinSession: DouyinSession?
    var loginPlatform: Platform?
    private(set) var douyinChangeCount = 0

    @ObservationIgnored private let repository: AccountRepository

    init(repository: AccountRepository) {
        self.repository = repository
        Task { [weak self] in
            let stored = await repository.session()
            let storedDouyin = await repository.douyinSession()
            guard let self else { return }
            if self.session == nil { self.session = stored }
            if self.douyinSession == nil { self.douyinSession = storedDouyin }
        }
    }

    func beginLogin(_ platform: Platform) {
        loginPlatform = platform
    }

    func completeLogin(_ platform: Platform, cookies: [String: String]) {
        loginPlatform = nil
        switch platform {
        case .douyu:
            let session = DouyuSession(cookies: cookies)
            self.session = session
            Task { [repository] in await repository.signIn(session) }
        case .douyin:
            let session = DouyinSession(cookies: cookies)
            douyinSession = session
            douyinChangeCount += 1
            Task { [repository] in await repository.signInDouyin(session) }
        }
    }

    func signOut(_ platform: Platform) {
        switch platform {
        case .douyu:
            session = nil
            Task { [repository] in await repository.signOut() }
        case .douyin:
            douyinSession = nil
            douyinChangeCount += 1
            Task { [repository] in await repository.signOutDouyin() }
        }
    }
}

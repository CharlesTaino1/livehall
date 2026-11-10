import Foundation

struct AccountRepository: Sendable {
    private let store: LocalStore

    init(store: LocalStore) {
        self.store = store
    }

    func session() async -> DouyuSession? {
        await store.currentSession()
    }

    func signIn(_ session: DouyuSession) async {
        await store.saveSession(session)
    }

    func signOut() async {
        await store.saveSession(nil)
    }

    func douyinSession() async -> DouyinSession? {
        await store.currentDouyinSession()
    }

    func signInDouyin(_ session: DouyinSession) async {
        await store.saveDouyinSession(session)
    }

    func signOutDouyin() async {
        await store.saveDouyinSession(nil)
    }
}

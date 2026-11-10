import Foundation

struct PreferencesRepository: Sendable {
    private let store: LocalStore

    init(store: LocalStore) {
        self.store = store
    }

    func current() async -> Preferences {
        await store.currentPreferences()
    }

    func update(_ change: @Sendable (inout Preferences) -> Void) async {
        await store.updatePreferences(change)
    }
}

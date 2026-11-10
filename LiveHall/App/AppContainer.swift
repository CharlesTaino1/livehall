@MainActor
final class AppContainer {
    let repository: LiveRepository
    let library: LibraryRepository
    let preferences: PreferencesRepository
    let account: AccountViewModel
    let images = ImageLoader()
    let router: Router
    let refresh = RefreshCenter()
    let preview: PreviewModel
    let network = NetworkMonitor()
    let multiView: MultiViewModel
    let shortVideo: ShortVideoViewModel
    let home: HomeViewModel
    let categories: CategoriesViewModel

    init() {
        let store = LocalStore()
        let accounts = AccountRepository(store: store)
        let http = HTTPClient()
        let douyin = DouyinAPI(http: http, account: accounts)
        repository = LiveRepository(
            douyu: DouyuAPI(http: http), douyin: douyin, douyuDanmaku: DouyuDanmakuClient(),
            douyinDanmaku: DouyinDanmakuClient(api: douyin), homeCache: HomeCache(), account: accounts)
        account = AccountViewModel(repository: accounts)
        router = Router(page: store.launchPage, miniWidth: store.launchMiniPlayerWidth)
        library = LibraryRepository(store: store)
        preferences = PreferencesRepository(store: store)
        preview = PreviewModel(repository: repository)
        multiView = MultiViewModel(
            launch: store.launchMultiView, repository: repository, library: library, preferences: preferences)
        shortVideo = ShortVideoViewModel(repository: repository, preferences: preferences, network: network)
        home = HomeViewModel(repository: repository, library: library, network: network)
        categories = CategoriesViewModel(repository: repository, network: network)
    }

    func makeCategoryRoomsViewModel(for category: LiveCategory) -> CategoryRoomsViewModel {
        CategoryRoomsViewModel(category: category, repository: repository, network: network)
    }

    func makeFollowsViewModel() -> FollowsViewModel {
        FollowsViewModel(repository: repository, library: library, network: network)
    }
}

import AppKit
import SwiftUI

struct RootView: View {
    let container: AppContainer

    @Namespace private var hero
    @State private var router: Router
    @State private var preview: PreviewModel
    @State private var account: AccountViewModel
    @State private var windowWidth: CGFloat = 0

    init(container: AppContainer) {
        self.container = container
        _router = State(initialValue: container.router)
        _preview = State(initialValue: container.preview)
        _account = State(initialValue: container.account)
    }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                Color.clear.frame(width: Theme.Sidebar.railWidth)
                NavigationStack(path: $router.path) {
                    SectionContent(container: container)
                        .navigationDestination(for: Route.self) { route in
                            switch route {
                            case .category(let category):
                                CategoryRoomsView(model: container.makeCategoryRoomsViewModel(for: category))
                            }
                        }
                }
            }
            .overlay(alignment: .leading) { Sidebar() }
            if let request = router.playing {
                let isMini = router.isPlayerMinimized
                let miniRange = miniWidthRange
                let miniWidth = min(max(router.miniWidth, miniRange.lowerBound), miniRange.upperBound)
                PlayerScreen(
                    repository: container.repository, library: container.library,
                    preferences: container.preferences, request: request, isMinimized: isMini
                )
                .id(request.roomID)
                .frame(
                    width: isMini ? miniWidth : nil,
                    height: isMini ? miniWidth / Theme.MiniPlayer.aspectRatio : nil
                )
                .clipShape(RoundedRectangle(cornerRadius: isMini ? Theme.Radius.control : 0))
                .overlay(alignment: .topLeading) {
                    if isMini {
                        MiniPlayerResizeHandle(
                            width: miniWidth, range: miniRange, resize: { router.miniWidth = $0 },
                            commit: { saveMiniWidth() })
                    }
                }
                .shadow(color: .black.opacity(isMini ? 0.55 : 0), radius: 18, y: 8)
                .padding(isMini ? Theme.MiniPlayer.margin : 0)
                .heroGeometry(id: isMini ? "mini-player" : request.cardID, in: hero)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .ignoresSafeArea()
                .transition(.opacity)
                .zIndex(1)
            }
            EscapeKey()
        }
        .sheet(item: $account.loginPlatform) { platform in
            LoginSheet(
                site: .site(for: platform),
                onSignedIn: { account.completeLogin(platform, cookies: $0) },
                onCancel: { account.loginPlatform = nil })
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { windowWidth = $0 }
        .environment(router)
        .environment(preview)
        .environment(container.refresh)
        .environment(account)
        .environment(container.multiView)
        .environment(\.imageLoader, container.images)
        .environment(\.heroNamespace, hero)
        .preferredColorScheme(.dark)
        .onChange(of: router.page) { _, page in
            Task { [preferences = container.preferences] in await preferences.update { $0.page = page } }
        }
        .onChange(of: router.isPlayerFull, initial: true) { _, isOpen in
            preview.setPlayerOpen(isOpen)
        }
        .task {
            for await notification in NotificationCenter.default.notifications(
                named: NSWindow.didChangeOcclusionStateNotification)
            {
                guard let window = notification.object as? NSWindow else { continue }
                preview.setWindowVisible(window.occlusionState.contains(.visible))
            }
        }
    }
}

extension RootView {
    fileprivate var miniWidthRange: ClosedRange<CGFloat> {
        let minimum = Theme.MiniPlayer.minWidth
        return minimum...max(minimum, windowWidth * Theme.MiniPlayer.maxWindowFraction)
    }

    fileprivate func saveMiniWidth() {
        let width = Double(router.miniWidth)
        Task { [preferences = container.preferences] in await preferences.update { $0.miniPlayerWidth = width } }
    }
}

private struct SectionContent: View {
    let container: AppContainer

    @Environment(Router.self) private var router

    var body: some View {
        switch router.section {
        case .home: HomeView(model: container.home)
        case .categories: CategoriesView(model: container.categories)
        case .follows: FollowsView(model: container.makeFollowsViewModel())
        case .multiview: MultiViewView(model: container.multiView)
        case .shortVideo: ShortVideoView(model: container.shortVideo)
        }
    }
}

private struct EscapeKey: View {
    @Environment(Router.self) private var router

    var body: some View {
        Button("返回") { router.escape() }
            .keyboardShortcut(.escape, modifiers: [])
            .frame(width: 0, height: 0)
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

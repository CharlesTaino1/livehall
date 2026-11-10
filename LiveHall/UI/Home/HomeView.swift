import SwiftUI

struct HomeView: View {
    @State private var model: HomeViewModel

    @Environment(Router.self) private var router

    init(model: HomeViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.Color.background
            switch model.phase {
            case .loading:
                HomeSkeleton()
            case .content:
                HomeContent(model: model)
            case .failed(let problem):
                StatusMessage(symbol: problem.symbol, message: problem.message, actionTitle: "重试") {
                    model.reload()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if model.isOffline, case .content = model.phase {
                OfflineBanner().padding(.top, Theme.Spacing.medium)
            }
            RefreshButton()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, Theme.Spacing.large)
                .padding(.trailing, Theme.Spacing.large)
        }
        .animation(Theme.Motion.controlsFade, value: model.isOffline)
        .ignoresSafeArea()
        .pageRefresh { await model.refresh() }
        .task { model.loadIfNeeded() }
        .onChange(of: !router.isPlayerFull) { _, isClosed in
            if isClosed { model.refreshLibraryRows() }
        }
    }
}

private struct HomeContent: View {
    let model: HomeViewModel

    @Environment(PreviewModel.self) private var preview
    @Environment(Router.self) private var router
    @State private var isOnScreen = false
    @State private var isBillboardVisible = true

    private var billboardRoomToPlay: RoomID? {
        isOnScreen && isBillboardVisible ? model.billboard?.id : nil
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let billboard = model.billboard {
                    Billboard(room: billboard)
                        .onScrollVisibilityChange(threshold: 0.4) { isBillboardVisible = $0 }
                }
                if !model.followingLive.isEmpty {
                    RoomRow(rowID: "following", title: "关注中正在直播", state: .loaded(model.followingLive))
                }
                if !model.recents.isEmpty {
                    RoomRow(rowID: "recents", title: "最近看过", state: .loaded(model.recents))
                }
                if model.categoriesFailed {
                    RoomRow(rowID: "categories", title: "热门分区", state: .failed) { model.retryCategories() }
                }
                ForEach(model.categoryRows.filter { $0.isVisible }) { row in
                    RoomRow(
                        rowID: "category-\(row.id)", title: row.category.name, state: row.state,
                        onRetry: { model.retry(category: row.category) },
                        onSelectTitle: { router.show(.category(row.category)) })
                }
            }
            .padding(.bottom, Theme.Spacing.large)
        }
        .scrollIndicators(.never)
        .pullToRefresh(topInset: Theme.Spacing.large)
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
        .onChange(of: billboardRoomToPlay, initial: true) { _, roomID in
            preview.setBillboard(roomID: roomID)
        }
    }
}

private struct HomeSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Theme.Color.placeholder.containerRelativeFrame(.vertical) { height, _ in max(360, height * 0.62) }
            RoomRow(rowID: "skeleton-1", title: "", state: .loading)
            RoomRow(rowID: "skeleton-2", title: "", state: .loading)
            Spacer(minLength: 0)
        }
    }
}

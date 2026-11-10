import SwiftUI

struct CategoryRoomsView: View {
    @State private var model: CategoryRoomsViewModel

    @Environment(Router.self) private var router

    init(model: CategoryRoomsViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.Color.background
            switch model.phase {
            case .loading:
                RoomsGrid(model: model, isLoading: true)
            case .content:
                RoomsGrid(model: model, isLoading: false)
            case .empty:
                StatusMessage(symbol: "tv.slash", message: "这个分区暂时没有直播", actionTitle: "返回") {
                    router.back()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let offline):
                StatusMessage(
                    symbol: offline ? "wifi.slash" : "exclamationmark.triangle",
                    message: offline ? "网络不可用，请检查连接" : "加载失败，请重试", actionTitle: "重试"
                ) {
                    Task { await model.load() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            PageHeader(
                title: model.category.name, subtitle: model.category.liveCount.map { "\($0) 个直播" },
                onBack: { router.back() })
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden()
        .pageRefresh { await model.refresh() }
        .task { await model.load() }
        .task { await model.retryWhenOnline() }
        .onChange(of: !router.isPlayerFull) { _, isClosed in
            if isClosed, case .failed = model.phase { Task { await model.load() } }
        }
    }
}

private struct RoomsGrid: View {
    let model: CategoryRoomsViewModel
    let isLoading: Bool

    var body: some View {
        ScrollView {
            if isLoading {
                SkeletonGrid()
                    .padding(.leading, Theme.Spacing.page)
                    .padding(.top, 88)
            } else {
                RoomGrid(rooms: model.rooms, rowID: "category-detail") { model.roomAppeared($0) }
                    .padding(.leading, Theme.Spacing.page)
                    .padding(.trailing, Theme.Spacing.medium)
                    .padding(.top, 88)
            }
            if !isLoading { GridFooter(model: model) }
        }
        .scrollIndicators(.never)
        .pullToRefresh()
    }
}

private struct GridFooter: View {
    let model: CategoryRoomsViewModel

    var body: some View {
        Group {
            if model.loadMoreFailed {
                HStack(spacing: Theme.Spacing.medium) {
                    Text("加载更多失败").foregroundStyle(Theme.Color.secondaryText)
                    Button("重试") { model.retryLoadMore() }
                }
            } else if model.isLoadingMore {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 64)
    }
}

import SwiftUI

struct FollowsView: View {
    @State private var model: FollowsViewModel

    @Environment(Router.self) private var router

    init(model: FollowsViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.Color.background
            switch model.phase {
            case .loading:
                FollowsGrid(rooms: nil)
            case .empty:
                StatusMessage(symbol: "heart", message: "还没有关注的主播", actionTitle: "回首页") { router.select(.home) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .content(let rooms):
                FollowsGrid(rooms: rooms)
            case .failed(let offline):
                StatusMessage(
                    symbol: offline ? "wifi.slash" : "exclamationmark.triangle",
                    message: offline ? "网络不可用，请检查连接" : "加载失败，请重试", actionTitle: "重试"
                ) {
                    Task { await model.load() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            PageHeader(title: "我的关注")
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden()
        .pageRefresh { await model.load() }
        .task { await model.load() }
        .task { await model.retryWhenOnline() }
        .onChange(of: !router.isPlayerFull) { _, isClosed in
            if isClosed { Task { await model.load() } }
        }
    }
}

private struct FollowsGrid: View {
    let rooms: [RoomSummary]?

    var body: some View {
        ScrollView {
            Group {
                if let rooms {
                    RoomGrid(rooms: rooms, rowID: "follows")
                } else {
                    SkeletonGrid()
                }
            }
            .padding(.leading, Theme.Spacing.page)
            .padding(.trailing, Theme.Spacing.medium)
            .padding(.top, 88)
            .padding(.bottom, Theme.Spacing.large)
        }
        .scrollIndicators(.never)
        .pullToRefresh()
    }
}

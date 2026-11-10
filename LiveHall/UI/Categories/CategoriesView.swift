import SwiftUI

struct CategoriesView: View {
    @State private var model: CategoriesViewModel

    init(model: CategoriesViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.Color.background
            switch model.phase {
            case .loading:
                CategoriesScroll(groups: nil, selectedGroupID: $model.selectedGroupID)
            case .content(let groups):
                CategoriesScroll(groups: groups, selectedGroupID: $model.selectedGroupID)
            case .failed(let offline):
                StatusMessage(
                    symbol: offline ? "wifi.slash" : "exclamationmark.triangle",
                    message: offline ? "网络不可用，请检查连接" : "加载失败，请重试", actionTitle: "重试"
                ) {
                    Task { await model.load() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            PageHeader(title: "分区")
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden()
        .pageRefresh { await model.refresh() }
        .task { await model.loadIfNeeded() }
        .task { await model.retryWhenOnline() }
    }
}

private struct CategoriesScroll: View {
    let groups: [CategoryGroup]?
    @Binding var selectedGroupID: String?

    private var visible: [LiveCategory] {
        groups?.first { $0.id == selectedGroupID }?.categories ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                GroupChips(groups: groups ?? [], selectedGroupID: $selectedGroupID)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: Theme.Poster.width), spacing: Theme.Card.spacing)],
                    alignment: .leading, spacing: Theme.Spacing.large
                ) {
                    if groups == nil {
                        ForEach(0..<12, id: \.self) { _ in PosterSkeleton() }
                    } else {
                        ForEach(visible) { category in PosterTile(category: category) }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, 96)
            .padding(.bottom, Theme.Spacing.large)
        }
        .scrollIndicators(.never)
        .pullToRefresh()
    }
}

private struct GroupChips: View {
    let groups: [CategoryGroup]
    @Binding var selectedGroupID: String?

    private func isSelected(_ group: CategoryGroup) -> Bool {
        selectedGroupID == group.id
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Spacing.small) {
                ForEach(groups) { group in
                    Button {
                        selectedGroupID = group.id
                    } label: {
                        Text(group.name)
                            .font(.callout.weight(.medium))
                            .padding(.horizontal, Theme.Spacing.medium)
                            .frame(height: 32)
                            .foregroundStyle(isSelected(group) ? Color.black : Theme.Color.secondaryText)
                            .background(isSelected(group) ? Color.white : Theme.Color.placeholder, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.never)
        .frame(height: 32)
    }
}

private struct PosterTile: View {
    let category: LiveCategory

    @Environment(Router.self) private var router
    @State private var isHovering = false

    private var posterSize: CGSize {
        CGSize(width: Theme.Poster.width, height: Theme.Poster.width / Theme.Poster.aspectRatio)
    }

    var body: some View {
        Button {
            router.show(.category(category))
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                Group {
                    if category.posterURL == nil {
                        Text(category.name)
                            .font(.title3.weight(.bold))
                            .multilineTextAlignment(.center)
                            .padding(Theme.Spacing.small)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Theme.Color.placeholder)
                    } else {
                        CoverImage(url: category.posterURL, size: posterSize)
                    }
                }
                .frame(width: posterSize.width, height: posterSize.height)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.name).font(.callout.weight(.semibold)).lineLimit(1)
                    if let liveCount = category.liveCount {
                        Text("\(liveCount) 个直播")
                            .font(.caption)
                            .foregroundStyle(Theme.Color.secondaryText)
                    }
                }
            }
            .frame(width: Theme.Poster.width, alignment: .leading)
            .scaleEffect(isHovering ? 1.05 : 1)
            .animation(Theme.Motion.cardExpand, value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(category.name)
    }
}

private struct PosterSkeleton: View {
    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.card)
            .fill(Theme.Color.placeholder)
            .frame(width: Theme.Poster.width, height: Theme.Poster.width / Theme.Poster.aspectRatio)
    }
}

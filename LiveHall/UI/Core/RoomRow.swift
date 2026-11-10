import SwiftUI

struct RoomRow: View {
    let rowID: String
    let title: String
    let state: LoadState<[RoomSummary]>
    var onRetry: (() -> Void)?
    var onSelectTitle: (() -> Void)?

    @State private var position: RoomID?
    @State private var edges = ScrollEdges()
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !title.isEmpty {
                RowTitle(title: title, onSelect: onSelectTitle)
                    .padding(.top, Theme.Spacing.medium)
                    .padding(.leading, Theme.Spacing.page)
            }
            if case .failed = state {
                RowFailure(onRetry: onRetry)
            } else {
                scroller
            }
        }
        .onHover { isHovering = $0 }
    }

    private var rooms: [RoomSummary]? {
        if case .loaded(let rooms) = state { rooms } else { nil }
    }

    private var scroller: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: Theme.Card.spacing) {
                if let rooms {
                    ForEach(rooms) { room in
                        RoomCard(room: room, rowID: rowID)
                    }
                } else {
                    ForEach(0..<8, id: \.self) { _ in SkeletonCard() }
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, Theme.Card.rowVerticalInset)
        }
        .contentMargins(.horizontal, Theme.Spacing.page, for: .scrollContent)
        .scrollIndicators(.never)
        .scrollClipDisabled()
        .scrollPosition(id: $position, anchor: .leading)
        .onScrollGeometryChange(for: ScrollEdges.self) { geometry in
            ScrollEdges(
                canGoBack: geometry.contentOffset.x > -geometry.contentInsets.leading + 1,
                canGoForward: geometry.contentOffset.x + geometry.containerSize.width
                    < geometry.contentSize.width + geometry.contentInsets.trailing - 1,
                viewportWidth: geometry.containerSize.width)
        } action: { _, new in
            edges = new
        }
        .overlay(alignment: .leading) { arrow(forward: false) }
        .overlay(alignment: .trailing) { arrow(forward: true) }
    }

    @ViewBuilder
    private func arrow(forward: Bool) -> some View {
        if isHovering, rooms != nil, forward ? edges.canGoForward : edges.canGoBack {
            Button {
                scroll(forward: forward)
            } label: {
                Image(systemName: forward ? "chevron.right" : "chevron.left")
                    .font(.title3.weight(.bold))
                    .frame(width: 36, height: 72)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.Spacing.small)
            .help(forward ? "向右滚动" : "向左滚动")
            .transition(.opacity)
        }
    }

    private func scroll(forward: Bool) {
        guard let rooms, !rooms.isEmpty else { return }
        let perPage = max(1, Int(edges.viewportWidth / (Theme.Card.width + Theme.Card.spacing)) - 1)
        let current = rooms.firstIndex { $0.id == position } ?? 0
        let target = min(max(current + (forward ? perPage : -perPage), 0), rooms.count - 1)
        withAnimation(Theme.Motion.hero) { position = rooms[target].id }
    }
}

private struct ScrollEdges: Equatable {
    var canGoBack = false
    var canGoForward = false
    var viewportWidth: CGFloat = 0
}

private struct RowFailure: View {
    let onRetry: (() -> Void)?

    var body: some View {
        HStack(spacing: Theme.Spacing.medium) {
            Text("加载失败").foregroundStyle(Theme.Color.secondaryText)
            if let onRetry { Button("重试", action: onRetry) }
        }
        .padding(.horizontal, Theme.Spacing.page)
        .frame(height: 96)
    }
}

private struct RowTitle: View {
    let title: String
    let onSelect: (() -> Void)?

    @State private var isHovering = false

    var body: some View {
        if let onSelect {
            Button(action: onSelect) {
                HStack(spacing: 4) {
                    Text(title).font(.title3.weight(.semibold))
                    Image(systemName: "chevron.right")
                        .font(.callout.weight(.bold))
                        .opacity(isHovering ? 1 : 0.4)
                }
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .help("查看全部")
        } else {
            Text(title).font(.title3.weight(.semibold))
        }
    }
}

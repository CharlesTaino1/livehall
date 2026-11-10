import Observation
import SwiftUI

@MainActor
@Observable
final class RefreshCenter {
    private(set) var isRefreshing = false
    private(set) var canRefresh = false
    private(set) var scrollToTopCount = 0

    @ObservationIgnored private var action: (() async -> Void)?
    @ObservationIgnored private var owner: UUID?

    func register(owner: UUID, action: @escaping () async -> Void) {
        self.owner = owner
        self.action = action
        canRefresh = true
    }

    func unregister(owner: UUID) {
        guard self.owner == owner else { return }
        self.owner = nil
        action = nil
        canRefresh = false
    }

    func refresh() {
        guard !isRefreshing, let action else { return }
        isRefreshing = true
        scrollToTopCount += 1
        Task {
            await action()
            isRefreshing = false
        }
    }
}

extension View {
    func pageRefresh(_ action: @escaping () async -> Void) -> some View {
        modifier(PageRefreshModifier(action: action))
    }

    func pullToRefresh(topInset: CGFloat = 72) -> some View {
        modifier(PullToRefreshModifier(topInset: topInset))
    }
}

private struct PageRefreshModifier: ViewModifier {
    let action: () async -> Void

    @Environment(RefreshCenter.self) private var center
    @State private var owner = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { center.register(owner: owner, action: action) }
            .onDisappear { center.unregister(owner: owner) }
    }
}

private struct PullToRefreshModifier: ViewModifier {
    private static let threshold: CGFloat = 70

    let topInset: CGFloat

    @Environment(RefreshCenter.self) private var center
    @State private var pull: CGFloat = 0
    @State private var position = ScrollPosition()

    func body(content: Content) -> some View {
        content
            .scrollBounceBehavior(.always, axes: .vertical)
            .scrollPosition($position)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentSize.width <= geometry.containerSize.width + 1
                    ? max(0, -(geometry.contentOffset.y + geometry.contentInsets.top)) : 0
            } action: { _, newValue in
                pull = newValue
            }
            .onScrollPhaseChange { old, new in
                if old == .interacting, new != .interacting, pull >= Self.threshold { center.refresh() }
            }
            .onChange(of: center.scrollToTopCount) {
                withAnimation(Theme.Motion.layout) { position.scrollTo(edge: .top) }
            }
            .overlay(alignment: .top) {
                RefreshIndicator(progress: min(pull / Self.threshold, 1), isRefreshing: center.isRefreshing)
                    .padding(.top, topInset)
                    .allowsHitTesting(false)
            }
    }
}

private struct RefreshIndicator: View {
    let progress: CGFloat
    let isRefreshing: Bool

    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
            if isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "arrow.down")
                    .font(.system(size: 13, weight: .semibold))
                    .rotationEffect(.degrees(progress >= 1 ? 180 : 0))
                    .animation(Theme.Motion.cardExpand, value: progress >= 1)
            }
        }
        .frame(width: 32, height: 32)
        .scaleEffect(isRefreshing ? 1 : max(progress, 0.01))
        .opacity(isRefreshing ? 1 : progress)
        .animation(Theme.Motion.controlsFade, value: isRefreshing)
    }
}

struct RefreshButton: View {
    @Environment(RefreshCenter.self) private var center

    var body: some View {
        if center.canRefresh {
            Button {
                center.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .symbolEffect(.rotate, isActive: center.isRefreshing)
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(center.isRefreshing)
            .help("刷新（⌘R）")
            .accessibilityLabel("刷新")
        }
    }
}

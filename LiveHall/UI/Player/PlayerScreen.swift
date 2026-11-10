import AppKit
import SwiftUI

struct PlayerScreen: View {
    @State private var model: PlayerViewModel
    @Environment(Router.self) private var router
    private let request: PlayRequest
    private let isMinimized: Bool

    init(
        repository: LiveRepository, library: LibraryRepository, preferences: PreferencesRepository,
        request: PlayRequest, isMinimized: Bool
    ) {
        _model = State(
            initialValue: PlayerViewModel(repository: repository, library: library, preferences: preferences))
        self.request = request
        self.isMinimized = isMinimized
    }

    var body: some View {
        ZStack {
            Theme.Color.background
            VideoSurface(layer: model.session.videoLayer)
            if case .loading = model.session.screen, request.coverURL != nil {
                CoverImage(url: request.coverURL, size: CGSize(width: 1280, height: 720))
            }
            if !isMinimized {
                DanmakuOverlay(
                    channel: model.session.danmakuChannel, isEnabled: model.isDanmakuEnabled,
                    settings: model.danmakuSettings
                )
                .allowsHitTesting(false)
            }
            RoomStatusOverlay(
                session: model.session, showsSpinner: request.coverURL == nil, retry: { model.retry() },
                exitTitle: "关闭", exit: { router.closePlayer() })
            if isMinimized {
                MiniChrome(model: model)
            } else {
                FullChrome(model: model)
            }
        }
        .preferredColorScheme(.dark)
        .onContinuousHover { phase in
            guard !isMinimized else { return }
            switch phase {
            case .active: model.controls.pointerMoved()
            case .ended: model.controls.pointerLeft()
            }
        }
        .onChange(of: model.controls.isVisible) { _, visible in
            if !visible, !isMinimized, model.controls.isPointerInside, model.session.screen == .playing {
                NSCursor.setHiddenUntilMouseMoves(true)
            }
        }
        .onChange(of: isMinimized, initial: true) { _, minimized in
            model.session.receivesDanmaku = !minimized
            if !minimized { model.controls.pointerMoved() }
        }
        .task { model.open(roomID: request.roomID) }
        .task {
            for await notification in NotificationCenter.default.notifications(
                named: NSWindow.didChangeOcclusionStateNotification)
            {
                guard let window = notification.object as? NSWindow else { continue }
                model.session.setVideoActive(window.occlusionState.contains(.visible))
            }
        }
        .onDisappear { model.close() }
    }
}

private struct FullChrome: View {
    let model: PlayerViewModel

    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Theme.Color.scrim, location: 0),
                    .init(color: Theme.Color.scrim.opacity(0.7), location: 0.45),
                    .init(color: .clear, location: 1),
                ], startPoint: .top, endPoint: .bottom
            )
            .frame(height: Theme.Player.topScrimHeight)
            .frame(maxHeight: .infinity, alignment: .top)
            .opacity(model.controls.isVisible ? 1 : 0)
            .animation(Theme.Motion.controlsFade, value: model.controls.isVisible)
            .allowsHitTesting(false)
            VStack {
                RoomBar(model: model)
                Spacer()
                ControlBar(model: model)
            }
            .padding(Theme.Spacing.medium)
            .opacity(model.controls.isVisible ? 1 : 0)
            .animation(Theme.Motion.controlsFade, value: model.controls.isVisible)
            .allowsHitTesting(model.controls.isVisible)
        }
    }
}

private struct MiniChrome: View {
    let model: PlayerViewModel
    @Environment(Router.self) private var router
    @State private var isHovering = false

    var body: some View {
        ZStack {
            Color.clear
            VStack {
                HStack(spacing: Theme.Spacing.small) {
                    if let room = model.session.room {
                        Text(room.anchorName)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                            .shadow(color: .black.opacity(0.6), radius: 3)
                    }
                    Spacer(minLength: Theme.Spacing.small)
                    button(
                        model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        help: model.isMuted ? "取消静音" : "静音"
                    ) {
                        model.isMuted.toggle()
                    }
                    button("arrow.up.left.and.arrow.down.right", help: "放大") { router.expandPlayer() }
                    button("xmark", help: "关闭直播间") { router.closePlayer() }
                }
                .padding(Theme.Spacing.small)
                .background(
                    LinearGradient(colors: [.black.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom)
                )
                Spacer()
            }
            .opacity(isHovering ? 1 : 0)
            .animation(Theme.Motion.controlsFade, value: isHovering)
            .allowsHitTesting(isHovering)
        }
        .contentShape(Rectangle())
        .onTapGesture { router.expandPlayer() }
        .onHover { isHovering = $0 }
    }

    private func button(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 26, height: 26)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct RoomBar: View {
    let model: PlayerViewModel
    @Environment(Router.self) private var router

    var body: some View {
        HStack(spacing: Theme.Spacing.medium) {
            Button {
                router.back()
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .help("返回（缩成小窗口继续看）")
            Button {
                router.closePlayer()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .help("关闭直播间")
            if let room = model.session.room {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(room.anchorName) · \(room.title)")
                        .font(.system(size: Theme.Player.titleFontSize, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(Theme.Color.primaryText)
                    RoomMeta(room: room, audienceCount: model.session.audienceCount, ranking: model.ranking)
                }
            }
            Spacer()
            FollowButton(model: model)
        }
        .padding(.leading, 72)
    }
}

private struct FollowButton: View {
    let model: PlayerViewModel

    var body: some View {
        Button {
            model.toggleFollow()
        } label: {
            Label(model.isFollowing ? "已关注" : "关注", systemImage: model.isFollowing ? "checkmark" : "plus")
                .font(.system(size: Theme.Player.metaFontSize, weight: .semibold))
                .foregroundStyle(Theme.Color.primaryText)
                .padding(.horizontal, Theme.Spacing.medium)
                .padding(.vertical, Theme.Spacing.small)
                .background(model.isFollowing ? Theme.Color.controlFill : Theme.Color.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(model.session.room == nil)
        .help(model.isFollowing ? "取消关注" : "关注主播")
    }
}

private struct RoomMeta: View {
    let room: LiveRoom
    let audienceCount: Int?
    let ranking: RoomRanking?

    var body: some View {
        HStack(spacing: Theme.Spacing.medium) {
            if !room.categoryName.isEmpty {
                Text(room.categoryName)
            }
            if let ranking {
                Text("\(ranking.name)第\(ranking.position)")
            }
            Label(formatPopularity(room.popularity), systemImage: "flame.fill")
            if let startedAt = room.startedAt {
                BroadcastDuration(startedAt: startedAt)
            }
            if let audienceCount {
                Text("\(room.id.platform.audienceLabel) \(formatPopularity(audienceCount))")
            }
            if let clubName = room.clubName {
                Text("公会 \(clubName)")
            }
        }
        .font(.system(size: Theme.Player.metaFontSize))
        .lineLimit(1)
        .foregroundStyle(Theme.Color.primaryText)
    }
}

private struct BroadcastDuration: View {
    let startedAt: Date

    var body: some View {
        TimelineView(.everyMinute) { context in
            Text("已播\(formatBroadcastDuration(context.date.timeIntervalSince(startedAt)))")
        }
    }
}

private struct ControlBar: View {
    enum Panel {
        case danmaku, line, quality
    }

    @Bindable var model: PlayerViewModel

    @Environment(Router.self) private var router
    @Environment(MultiViewModel.self) private var multiView
    @State private var openPanel: Panel?

    private func isOpen(_ panel: Panel) -> Binding<Bool> {
        Binding(
            get: { openPanel == panel },
            set: { isOpen in
                if isOpen {
                    openPanel = panel
                } else if openPanel == panel {
                    openPanel = nil
                }
            })
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.medium) {
            Button {
                model.isMuted.toggle()
            } label: {
                Image(systemName: model.isMuted || model.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 22)
            }
            .help(model.isMuted ? "取消静音" : "静音")
            Slider(value: $model.volume, in: 0...1)
                .frame(width: 120)
            Button {
                model.isDanmakuEnabled.toggle()
            } label: {
                Image(systemName: model.isDanmakuEnabled ? "text.bubble.fill" : "text.bubble")
                    .frame(width: 22)
            }
            .help(model.isDanmakuEnabled ? "关闭弹幕" : "开启弹幕")
            Button {
                openPanel = openPanel == .danmaku ? nil : .danmaku
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .frame(width: 22)
            }
            .help("弹幕设置")
            .popover(isPresented: isOpen(.danmaku), arrowEdge: .top) {
                DanmakuSettingsView(settings: $model.danmakuSettings)
            }
            Button {
                openPanel = openPanel == .line ? nil : .line
            } label: {
                Text(lineTitle)
            }
            .disabled(model.session.lines.isEmpty)
            .help("选择线路")
            .popover(isPresented: isOpen(.line), arrowEdge: .top) {
                ChoiceList(
                    options: [.init(value: "", title: "自动")]
                        + model.session.lines.map { .init(value: $0.cdn, title: $0.name) },
                    selection: model.session.lines.contains { $0.cdn == model.session.streamPreference.cdn }
                        ? model.session.streamPreference.cdn : ""
                ) { cdn in
                    model.selectLine(cdn: cdn)
                    openPanel = nil
                }
            }
            Button {
                openPanel = openPanel == .quality ? nil : .quality
            } label: {
                Text(qualityTitle)
            }
            .disabled(model.session.qualities.isEmpty)
            .help("选择画质")
            .popover(isPresented: isOpen(.quality), arrowEdge: .top) {
                ChoiceList(
                    options: [.init(value: -1, title: "自动")]
                        + model.session.qualities.map { .init(value: $0.rate, title: $0.name) },
                    selection: model.session.qualities.contains { $0.rate == model.session.streamPreference.rate }
                        ? model.session.streamPreference.rate : -1
                ) { rate in
                    model.selectQuality(rate: rate)
                    openPanel = nil
                }
            }
            Button {
                guard let roomID = model.session.room?.id else { return }
                multiView.add(roomID: roomID)
                router.showMultiView()
            } label: {
                Image(systemName: "rectangle.split.2x2")
                    .frame(width: 22)
            }
            .disabled(model.session.room == nil)
            .help("加入多看")
            Button {
                NSApp.keyWindow?.toggleFullScreen(nil)
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .frame(width: 22)
            }
            .help("全屏")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.Spacing.medium)
        .frame(height: 40)
        .background(.ultraThinMaterial, in: Capsule())
        .onChange(of: openPanel) { _, panel in
            model.controls.setPinned(panel != nil)
        }
    }

    private var lineTitle: String {
        model.session.lines.first { $0.cdn == model.session.currentCDN }?.name ?? "线路"
    }

    private var qualityTitle: String {
        model.session.qualities.first { $0.rate == model.session.currentRate }?.name ?? "画质"
    }
}

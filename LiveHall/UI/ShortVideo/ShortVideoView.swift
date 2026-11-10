import AppKit
import SwiftUI

struct ShortVideoView: View {
    @State private var model: ShortVideoViewModel
    @State private var pager = ScrollPager()

    @Environment(Router.self) private var router
    @Environment(AccountViewModel.self) private var account
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: ShortVideoViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        GeometryReader { proxy in
            let panelWidth = model.isCommentsOpen ? ShortVideoLayout.commentsWidth : 0
            let stage = CGSize(width: proxy.size.width - panelWidth, height: proxy.size.height)
            ZStack {
                Theme.Color.background
                Group {
                    switch model.phase {
                    case .loading:
                        RoundedRectangle(cornerRadius: Theme.Radius.card)
                            .fill(Theme.Color.placeholder)
                            .aspectRatio(ShortVideoLayout.placeholderRatio, contentMode: .fit)
                            .padding(Theme.Spacing.large)
                    case .content:
                        ForEach(model.slots) { slot in
                            ShortVideoPage(
                                slot: slot, player: model.players[slot.id], model: model, container: stage
                            )
                            .offset(y: CGFloat(slot.offset) * stage.height)
                            .transition(.identity)
                        }
                    case .failed(let offline):
                        StatusMessage(
                            symbol: offline ? "wifi.slash" : "exclamationmark.triangle",
                            message: offline ? "网络不可用，请检查连接" : "加载失败，请重试", actionTitle: "重试"
                        ) {
                            Task { await model.load() }
                        }
                    }
                }
                .frame(width: stage.width, height: stage.height)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
                PageHeader(title: "短视频")
                    .frame(width: stage.width)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                if model.isCommentsOpen, let comments = model.comments {
                    CommentsPanel(model: comments, close: { toggleComments() })
                        .frame(width: ShortVideoLayout.commentsWidth)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .transition(.move(edge: .trailing))
                }
                ShortcutKeys(model: model, turn: turn, toggleComments: toggleComments)
            }
            .animation(reduceMotion ? nil : Theme.Motion.layout, value: model.isCommentsOpen)
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden()
        .pageRefresh { await model.refresh() }
        .task { await model.activate() }
        .task { await model.retryWhenOnline() }
        .task {
            for await notification in NotificationCenter.default.notifications(
                named: NSWindow.didChangeOcclusionStateNotification)
            {
                guard let window = notification.object as? NSWindow else { continue }
                model.setWindowVisible(window.occlusionState.contains(.visible))
            }
        }
        .onChange(of: model.isCommentsOpen, initial: true) { _, isOpen in
            pager.isEnabled = !isOpen
        }
        .onChange(of: account.douyinChangeCount) {
            Task { await model.load() }
        }
        .onAppear {
            pager.start { turn($0) }
            router.backHandler = { model.closeCommentsIfOpen() }
        }
        .onDisappear {
            pager.stop()
            router.backHandler = nil
            model.deactivate()
        }
    }

    private func toggleComments() {
        withAnimation(reduceMotion ? nil : Theme.Motion.layout) { model.toggleComments() }
    }

    private func turn(_ direction: Int) {
        withAnimation(reduceMotion ? nil : Theme.Motion.layout) {
            if direction > 0 { model.next() } else { model.previous() }
        }
    }
}

private enum ShortVideoLayout {
    static let placeholderRatio: CGFloat = 9.0 / 16.0
    static let avatarSize: CGFloat = 44
    static let progressHeight: CGFloat = 3
    static let scrimHeight: CGFloat = 220
    static let infoMaxWidth: CGFloat = 360
    static let danmakuTopInset: CGFloat = 64
    static let commentsWidth: CGFloat = 380
    static let volumeSliderWidth: CGFloat = 90
}

private struct ShortVideoPage: View {
    let slot: ShortVideoViewModel.Slot
    let player: ClipPlayer?
    let model: ShortVideoViewModel
    let container: CGSize

    private var video: ShortVideo { slot.video }

    private var fitted: CGSize {
        let width = min(container.width, container.height * video.aspectRatio)
        return CGSize(width: width, height: width / video.aspectRatio)
    }

    var body: some View {
        ZStack {
            CoverImage(url: video.coverURL, size: fitted)
                .aspectRatio(video.aspectRatio, contentMode: .fit)
                .opacity(player?.isReadyForDisplay == true ? 0 : 1)
            if let player {
                VideoSurface(layer: player.layer)
                    .allowsHitTesting(false)
            }
            if slot.offset == 0 {
                Overlay(video: video, player: player, model: model)
                    .frame(width: fitted.width, height: fitted.height)
            }
        }
        .frame(width: container.width, height: container.height)
        .contentShape(Rectangle())
        .onTapGesture {
            if slot.offset == 0 { model.togglePause() }
        }
    }
}

private struct Overlay: View {
    let video: ShortVideo
    let player: ClipPlayer?
    let model: ShortVideoViewModel

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            DanmakuOverlay(
                channel: model.danmaku.channel, isEnabled: model.danmaku.isEnabled, settings: model.settings.danmaku
            )
            .padding(.top, ShortVideoLayout.danmakuTopInset)
            .allowsHitTesting(false)
            LinearGradient(colors: [.clear, Theme.Color.scrim], startPoint: .top, endPoint: .bottom)
                .frame(height: ShortVideoLayout.scrimHeight)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                HStack(spacing: Theme.Spacing.small) {
                    CoverImage(
                        url: video.avatarURL,
                        size: CGSize(width: ShortVideoLayout.avatarSize, height: ShortVideoLayout.avatarSize)
                    )
                    .frame(width: ShortVideoLayout.avatarSize, height: ShortVideoLayout.avatarSize)
                    .clipShape(Circle())
                    Text(video.authorName).font(.headline).lineLimit(1)
                }
                if !video.description.isEmpty {
                    Text(video.description)
                        .font(.callout)
                        .foregroundStyle(Theme.Color.secondaryText)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: ShortVideoLayout.infoMaxWidth, alignment: .leading)
            .padding(Theme.Spacing.medium)
            .padding(.bottom, ShortVideoLayout.progressHeight)
            .allowsHitTesting(false)
            SideActions(video: video, model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(Theme.Spacing.medium)
                .padding(.bottom, ShortVideoLayout.progressHeight)
            if model.isPaused {
                Image(systemName: "play.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.white.opacity(0.8))
                    .shadow(radius: 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
            if let player {
                if player.isBuffering {
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                }
                if player.hasFailed {
                    Text("这条放不了，往下翻看下一条")
                        .font(.callout)
                        .foregroundStyle(Theme.Color.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                }
                ProgressLine(player: player)
            }
        }
        .foregroundStyle(Theme.Color.primaryText)
    }
}

private struct SideActions: View {
    let video: ShortVideo
    let model: ShortVideoViewModel

    var body: some View {
        VStack(spacing: Theme.Spacing.medium) {
            VStack(spacing: 2) {
                Image(systemName: "heart.fill").font(.title2)
                Text(formatPopularity(video.likeCount)).font(.caption)
            }
            Button {
                model.toggleComments()
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: model.isCommentsOpen ? "ellipsis.bubble" : "ellipsis.bubble.fill")
                        .font(.title2)
                    Text(formatPopularity(video.commentCount)).font(.caption)
                }
            }
            .buttonStyle(.plain)
            .help("评论（C）")
            .accessibilityLabel("评论")
            DanmakuControl(model: model)
            RoundButton(
                symbol: model.isAutoNext ? "forward.end.fill" : "repeat",
                help: model.isAutoNext ? "播完自动下一条，点一下改成循环" : "循环当前这条，点一下改成播完自动下一条"
            ) { model.toggleAutoNext() }
            VolumeControl(model: model)
        }
        .shadow(color: .black.opacity(0.4), radius: 4)
    }
}

private struct DanmakuControl: View {
    let model: ShortVideoViewModel

    @State private var isSettingsOpen = false

    var body: some View {
        VStack(spacing: Theme.Spacing.small) {
            RoundButton(
                symbol: model.danmaku.isEnabled ? "text.bubble.fill" : "text.bubble",
                help: model.danmaku.isEnabled ? "关闭弹幕（D）" : "开启弹幕（D）"
            ) { model.toggleDanmaku() }
            RoundButton(symbol: "slider.horizontal.3", help: "弹幕设置") { isSettingsOpen.toggle() }
                .popover(isPresented: $isSettingsOpen, arrowEdge: .leading) {
                    DanmakuSettingsView(settings: Bindable(model.settings).danmaku)
                }
        }
    }
}

private struct RoundButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct VolumeControl: View {
    let model: ShortVideoViewModel

    @State private var isHovering = false

    private var isSilent: Bool { model.settings.isMuted || model.settings.volume == 0 }

    var body: some View {
        HStack(spacing: Theme.Spacing.small) {
            if isHovering {
                Slider(
                    value: Binding(
                        get: { model.settings.isMuted ? 0 : model.settings.volume },
                        set: { model.setVolume($0) }),
                    in: 0...1
                )
                .frame(width: ShortVideoLayout.volumeSliderWidth)
                .transition(.opacity)
            }
            RoundButton(
                symbol: isSilent ? "speaker.slash.fill" : "speaker.wave.2.fill",
                help: isSilent ? "取消静音（M）" : "静音（M）"
            ) { model.toggleMute() }
        }
        .frame(width: 36, alignment: .trailing)
        .fixedSize()
        .frame(width: 36, alignment: .trailing)
        .onHover { isHovering = $0 }
        .animation(Theme.Motion.controlsFade, value: isHovering)
    }
}

private struct ProgressLine: View {
    let player: ClipPlayer

    var body: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(.white.opacity(0.85))
                .frame(width: proxy.size.width * player.progress, height: ShortVideoLayout.progressHeight)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .allowsHitTesting(false)
    }
}

private struct ShortcutKeys: View {
    let model: ShortVideoViewModel
    let turn: (Int) -> Void
    let toggleComments: () -> Void

    var body: some View {
        Group {
            Button("上一条") { turn(-1) }.keyboardShortcut(.upArrow, modifiers: [])
            Button("下一条") { turn(1) }.keyboardShortcut(.downArrow, modifiers: [])
            Button("暂停或继续") { model.togglePause() }.keyboardShortcut(.space, modifiers: [])
            Button("快退") { model.seek(by: -5) }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("快进") { model.seek(by: 5) }.keyboardShortcut(.rightArrow, modifiers: [])
            Button("静音") { model.toggleMute() }.keyboardShortcut("m", modifiers: [])
            Button("评论") { toggleComments() }.keyboardShortcut("c", modifiers: [])
            Button("弹幕") { model.toggleDanmaku() }.keyboardShortcut("d", modifiers: [])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

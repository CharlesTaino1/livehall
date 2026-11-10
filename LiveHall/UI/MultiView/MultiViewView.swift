import AppKit
import SwiftUI

struct MultiViewView: View {
    let model: MultiViewModel

    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let frames = MultiViewGeometry.frames(
                layout: model.layout, maximized: maximizedIndex, in: proxy.size)
            ZStack {
                Theme.Color.background
                ForEach(model.cells) { cell in
                    MultiViewCellView(cell: cell, model: model)
                        .placed(in: frames[cell.index], isHidden: isHidden(cell.roomID))
                }
                ForEach(model.visibleRoomIDs.count..<model.layout.capacity, id: \.self) { index in
                    AddRoomTile(model: model)
                        .placed(in: frames[index], isHidden: model.maximizedRoomID != nil)
                }
                ControlBar(model: model)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(Theme.Spacing.medium)
                    .opacity(model.controls.isVisible ? 1 : 0)
                    .animation(Theme.Motion.controlsFade, value: model.controls.isVisible)
                    .allowsHitTesting(model.controls.isVisible)
                ShortcutKeys(model: model)
            }
            .animation(reduceMotion ? nil : Theme.Motion.layout, value: model.layout)
        }
        .ignoresSafeArea()
        .onContinuousHover { phase in
            if case .active = phase { model.controls.pointerMoved() }
        }
        .onChange(of: model.controls.isVisible) { _, visible in
            if !visible { NSCursor.setHiddenUntilMouseMoves(true) }
        }
        .task { await model.activate() }
        .task {
            for await notification in NotificationCenter.default.notifications(
                named: NSWindow.didChangeOcclusionStateNotification)
            {
                guard let window = notification.object as? NSWindow else { continue }
                model.setWindowVisible(window.occlusionState.contains(.visible))
            }
        }
        .onAppear { router.backHandler = { model.restoreFromMaximized() } }
        .onDisappear {
            router.backHandler = nil
            model.deactivate()
        }
    }

    private var maximizedIndex: Int? {
        model.maximizedRoomID.flatMap { model.visibleRoomIDs.firstIndex(of: $0) }
    }

    private func isHidden(_ roomID: RoomID) -> Bool {
        model.maximizedRoomID != nil && model.maximizedRoomID != roomID
    }
}

extension View {
    fileprivate func placed(in frame: CGRect, isHidden: Bool) -> some View {
        self
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .opacity(isHidden ? 0 : 1)
            .allowsHitTesting(!isHidden)
    }
}

private struct ControlBar: View {
    @Bindable var model: MultiViewModel

    @State private var isDanmakuPanelOpen = false

    var body: some View {
        HStack(spacing: Theme.Spacing.medium) {
            ForEach(MultiViewLayout.allCases, id: \.self) { layout in
                Button {
                    model.setLayout(layout)
                } label: {
                    Image(systemName: layout.symbol)
                        .frame(width: 22)
                        .foregroundStyle(model.layout == layout ? .white : Theme.Color.tertiaryText)
                }
                .help(layout.title)
            }
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
                isDanmakuPanelOpen.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .frame(width: 22)
            }
            .help("弹幕设置")
            .popover(isPresented: $isDanmakuPanelOpen, arrowEdge: .top) {
                DanmakuSettingsView(settings: $model.danmakuSettings)
            }
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
        .onChange(of: isDanmakuPanelOpen) { _, isOpen in
            model.controls.setPinned(isOpen)
        }
    }
}

private struct ShortcutKeys: View {
    let model: MultiViewModel

    var body: some View {
        ForEach(0..<MultiViewState.maxRooms, id: \.self) { index in
            Button("第 \(index + 1) 路") { model.focus(index: index) }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension MultiViewLayout {
    fileprivate var symbol: String {
        switch self {
        case .pair: "rectangle.split.2x1"
        case .quad: "rectangle.split.2x2"
        }
    }

    fileprivate var title: String {
        switch self {
        case .pair: "左右两路"
        case .quad: "四路"
        }
    }
}

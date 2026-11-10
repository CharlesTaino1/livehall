import SwiftUI

struct MultiViewCellView: View {
    let cell: MultiViewModel.Cell
    let model: MultiViewModel

    @State private var isHovering = false

    private var isFocused: Bool { model.focusedRoomID == cell.roomID }
    private var isMaximized: Bool { model.maximizedRoomID == cell.roomID }

    var body: some View {
        ZStack {
            Theme.Color.background
            VideoSurface(layer: cell.session.videoLayer)
            if isFocused {
                DanmakuOverlay(
                    channel: cell.session.danmakuChannel, isEnabled: model.isDanmakuEnabled,
                    settings: model.danmakuSettings
                )
                .allowsHitTesting(false)
            }
            RoomStatusOverlay(
                session: cell.session, showsSpinner: true, retry: { model.retry(roomID: cell.roomID) },
                exitTitle: "移除", exit: { model.remove(roomID: cell.roomID) })
            CellChrome(cell: cell, model: model, isFocused: isFocused, isMaximized: isMaximized)
                .opacity(isHovering ? 1 : 0)
                .animation(Theme.Motion.controlsFade, value: isHovering)
                .allowsHitTesting(isHovering)
        }
        .clipped()
        .overlay {
            if isFocused, !isMaximized, model.visibleRoomIDs.count > 1 {
                Rectangle().strokeBorder(Theme.Color.accent, lineWidth: Theme.MultiView.focusBorderWidth)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.focus(roomID: cell.roomID) }
        .simultaneousGesture(TapGesture(count: 2).onEnded { model.toggleMaximize(roomID: cell.roomID) })
        .onHover { isHovering = $0 }
    }
}

private struct CellChrome: View {
    let cell: MultiViewModel.Cell
    let model: MultiViewModel
    let isFocused: Bool
    let isMaximized: Bool

    var body: some View {
        VStack {
            HStack(spacing: Theme.Spacing.small) {
                if let room = cell.session.room {
                    Text("\(room.anchorName) · \(room.title)")
                        .font(.callout)
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.6), radius: 3)
                }
                Spacer(minLength: Theme.Spacing.small)
                button(isFocused ? "speaker.wave.2.fill" : "speaker.slash", help: "把声音给这一路") {
                    model.focus(roomID: cell.roomID)
                }
                button(
                    isMaximized ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                    help: isMaximized ? "还原" : "最大化"
                ) {
                    withAnimation(Theme.Motion.layout) { model.toggleMaximize(roomID: cell.roomID) }
                }
                button("xmark", help: "移除这一路") {
                    withAnimation(Theme.Motion.layout) { model.remove(roomID: cell.roomID) }
                }
            }
            .padding(Theme.Spacing.small)
            .background(
                LinearGradient(colors: [.black.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom)
            )
            Spacer()
        }
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

struct AddRoomTile: View {
    let model: MultiViewModel

    @State private var isPickerOpen = false
    @State private var isHovering = false

    var body: some View {
        Button {
            isPickerOpen = true
        } label: {
            VStack(spacing: Theme.Spacing.small) {
                Image(systemName: "plus").font(.system(size: 30, weight: .light))
                Text("添加直播间").font(.callout)
            }
            .foregroundStyle(isHovering ? .white : Theme.Color.secondaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isHovering ? .white.opacity(0.14) : Theme.Color.placeholder)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .popover(isPresented: $isPickerOpen, arrowEdge: .bottom) {
            RoomPickerView(model: model.makePicker(), excluding: Set(model.roomIDs)) {
                roomID in
                isPickerOpen = false
                withAnimation(Theme.Motion.layout) { model.add(roomID: roomID) }
            }
        }
        .help("添加直播间")
    }
}

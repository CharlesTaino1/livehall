import SwiftUI

struct RoomCard: View {
    let room: RoomSummary
    let rowID: String

    @Environment(Router.self) private var router
    @Environment(PreviewModel.self) private var preview
    @Environment(MultiViewModel.self) private var multiView
    @Environment(\.heroNamespace) private var hero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var cardID: String { "\(rowID)-\(room.id)" }
    private var isExpanded: Bool { preview.expandedCardID == cardID }
    private var coverSize: CGSize {
        CGSize(width: Theme.Card.width, height: Theme.Card.width / Theme.Card.aspectRatio)
    }

    var body: some View {
        Button {
            router.play(PlayRequest(roomID: room.id, cardID: cardID, coverURL: room.largeCoverURL))
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                cover
                    .aspectRatio(Theme.Card.aspectRatio, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
                    .overlay(alignment: .bottomLeading) { CardBadge(room: room).padding(Theme.Spacing.small) }
                    .overlay(alignment: .topLeading) {
                        SourceTag(platform: room.id.platform).padding(Theme.Spacing.small)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(room.title).font(.callout.weight(.semibold)).lineLimit(1)
                    Text(subtitle).font(.caption).foregroundStyle(Theme.Color.secondaryText).lineLimit(1)
                }
            }
            .frame(width: Theme.Card.width, alignment: .leading)
            .scaleEffect(isExpanded ? Theme.Card.hoverScale : 1)
            .shadow(color: .black.opacity(isExpanded ? 0.6 : 0), radius: 18, y: 8)
            .animation(Theme.Motion.cardExpand, value: isExpanded)
        }
        .buttonStyle(PressableStyle())
        .zIndex(isExpanded ? 1 : 0)
        .onHover { isHovering in
            guard room.isLive, !reduceMotion else { return }
            let target = PreviewModel.Hover(cardID: cardID, roomID: room.id)
            if isHovering {
                preview.pointerEntered(target)
            } else {
                preview.pointerExited(target)
            }
        }
        .contextMenu {
            if room.isLive {
                Button("加入多看", systemImage: "rectangle.split.2x2") {
                    multiView.add(roomID: room.id)
                    router.select(.multiview)
                }
            }
        }
        .help(room.title)
    }

    private var subtitle: String {
        room.categoryName.isEmpty ? room.anchorName : "\(room.anchorName) · \(room.categoryName)"
    }

    @ViewBuilder
    private var cover: some View {
        if router.isPlayerFull, router.playing?.cardID == cardID {
            Color.clear
        } else {
            ZStack {
                CoverImage(url: room.coverURL, size: coverSize)
                    .saturation(room.isLive ? 1 : 0)
                    .opacity(room.isLive ? 1 : Theme.Card.offlineOpacity)
                if isExpanded, preview.isShowingVideo, let layer = preview.videoLayer {
                    VideoSurface(layer: layer)
                }
            }
            .heroGeometry(id: cardID, in: hero)
        }
    }
}

private struct CardBadge: View {
    let room: RoomSummary

    var body: some View {
        if room.isLive {
            Label(formatPopularity(room.popularity), systemImage: "flame.fill")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.black.opacity(0.55), in: Capsule())
        } else {
            Text("未开播")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.black.opacity(0.55), in: Capsule())
        }
    }
}

private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .fill(Theme.Color.placeholder)
                .frame(width: Theme.Card.width, height: Theme.Card.width / Theme.Card.aspectRatio)
            line(width: Theme.Card.width * 0.8, height: 12)
            line(width: Theme.Card.width * 0.5, height: 10)
        }
        .frame(width: Theme.Card.width, alignment: .leading)
    }

    private func line(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3).fill(Theme.Color.placeholder).frame(width: width, height: height)
    }
}

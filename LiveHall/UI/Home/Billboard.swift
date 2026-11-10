import SwiftUI

struct Billboard: View {
    let room: RoomSummary

    @Environment(Router.self) private var router
    @Environment(PreviewModel.self) private var preview
    @Environment(\.heroNamespace) private var hero

    private var cardID: String { "billboard-\(room.id)" }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backdrop
            LinearGradient(
                colors: [.clear, Theme.Color.background.opacity(0.85), Theme.Color.background],
                startPoint: .init(x: 0.5, y: 0.45), endPoint: .bottom)
            LinearGradient(
                colors: [Theme.Color.background.opacity(0.7), .clear],
                startPoint: .leading, endPoint: .init(x: 0.6, y: 0.5))
            details
        }
        .containerRelativeFrame(.vertical) { height, _ in max(360, height * 0.62) }
        .clipped()
    }

    @ViewBuilder
    private var backdrop: some View {
        if router.isPlayerFull, router.playing?.cardID == cardID {
            Color.clear
        } else {
            ZStack {
                CoverImage(url: room.largeCoverURL, size: CGSize(width: 1280, height: 720))
                if preview.isBillboardActive, preview.isShowingVideo, let layer = preview.videoLayer {
                    VideoSurface(layer: layer)
                }
            }
            .heroGeometry(id: cardID, in: hero)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Text(room.anchorName).font(.system(size: 40, weight: .bold)).lineLimit(1)
            Text(room.title).font(.title3).lineLimit(2).foregroundStyle(Theme.Color.secondaryText)
            HStack(spacing: Theme.Spacing.medium) {
                SourceTag(platform: room.id.platform)
                if !room.categoryName.isEmpty {
                    Text(room.categoryName)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.18), in: Capsule())
                }
                Label(formatPopularity(room.popularity), systemImage: "flame.fill")
            }
            .font(.callout)
            .foregroundStyle(Theme.Color.secondaryText)
            Button {
                router.play(PlayRequest(roomID: room.id, cardID: cardID, coverURL: room.largeCoverURL))
            } label: {
                Label("观看", systemImage: "play.fill")
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, Theme.Spacing.medium)
                    .frame(height: 40)
            }
            .buttonStyle(WatchButtonStyle())
            .padding(.top, Theme.Spacing.small)
        }
        .frame(maxWidth: 560, alignment: .leading)
        .padding(.leading, Theme.Spacing.page)
        .padding(.bottom, Theme.Spacing.large * 2)
        .shadow(color: .black.opacity(0.5), radius: 8)
    }
}

private struct WatchButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.black)
            .background(
                .white.opacity(configuration.isPressed ? 0.75 : 1),
                in: RoundedRectangle(cornerRadius: Theme.Radius.control))
    }
}

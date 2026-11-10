import SwiftUI

struct RoomStatusOverlay: View {
    let session: RoomSession
    let showsSpinner: Bool
    let retry: () -> Void
    let exitTitle: String
    let exit: () -> Void

    var body: some View {
        switch session.screen {
        case .idle:
            EmptyView()
        case .loading:
            if showsSpinner { ProgressView().controlSize(.large) }
        case .playing:
            if let interruption = session.interruption {
                HStack(spacing: Theme.Spacing.small) {
                    ProgressView().controlSize(.small)
                    Text(interruption)
                }
                .padding(.horizontal, Theme.Spacing.medium)
                .padding(.vertical, Theme.Spacing.small)
                .background(.ultraThinMaterial, in: Capsule())
            }
        case .notice(let notice):
            VStack(spacing: Theme.Spacing.medium) {
                Text(notice.message).font(.title3).foregroundStyle(Theme.Color.secondaryText)
                if notice.isRetryable {
                    Button("重试", action: retry)
                } else {
                    Button(exitTitle, action: exit)
                }
            }
            .controlSize(.large)
            .padding(Theme.Spacing.large)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
        }
    }
}

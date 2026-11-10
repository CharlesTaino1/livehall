import SwiftUI

struct PageHeader: View {
    let title: String
    var subtitle: String?
    var onBack: (() -> Void)?

    var body: some View {
        HStack(spacing: Theme.Spacing.medium) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .frame(width: 32, height: 32)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .help("返回")
            }
            Text(title).font(.title2.weight(.bold))
            if let subtitle {
                Text(subtitle).font(.callout).foregroundStyle(Theme.Color.secondaryText)
            }
            Spacer()
            RefreshButton()
        }
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.top, Theme.Spacing.large)
        .padding(.bottom, Theme.Spacing.large)
        .background(
            LinearGradient(
                colors: [Theme.Color.background.opacity(0.92), .clear], startPoint: .top, endPoint: .bottom)
        )
    }
}

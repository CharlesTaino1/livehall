import SwiftUI

struct OfflineBanner: View {
    var body: some View {
        Label("网络不可用，正在显示上次的内容", systemImage: "wifi.slash")
            .font(.callout)
            .padding(.horizontal, Theme.Spacing.medium)
            .padding(.vertical, Theme.Spacing.small)
            .background(.ultraThinMaterial, in: Capsule())
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

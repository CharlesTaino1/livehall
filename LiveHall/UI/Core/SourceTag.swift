import SwiftUI

struct SourceTag: View {
    let platform: Platform

    var body: some View {
        Text(platform.name)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.black.opacity(0.55), in: Capsule())
            .accessibilityLabel("来自\(platform.name)")
    }
}

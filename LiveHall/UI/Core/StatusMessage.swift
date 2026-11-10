import SwiftUI

struct StatusMessage: View {
    let symbol: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.medium) {
            Image(systemName: symbol).font(.system(size: 34)).foregroundStyle(Theme.Color.tertiaryText)
            Text(message).font(.title3).foregroundStyle(Theme.Color.secondaryText)
            Button(actionTitle, action: action).controlSize(.large)
        }
    }
}

import SwiftUI

struct ChoiceList<Value: Hashable>: View {
    struct Option {
        let value: Value
        let title: String
    }

    let options: [Option]
    let selection: Value
    let onSelect: (Value) -> Void

    var body: some View {
        VStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                ChoiceRow(title: option.title, isSelected: option.value == selection) {
                    onSelect(option.value)
                }
            }
        }
        .padding(Theme.Spacing.small)
        .frame(minWidth: 168)
    }
}

private struct ChoiceRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer(minLength: Theme.Spacing.medium)
                if isSelected { Image(systemName: "checkmark") }
            }
            .padding(.horizontal, Theme.Spacing.small)
            .frame(height: 30)
            .contentShape(Rectangle())
            .background(
                .white.opacity(isHovering ? 0.12 : 0), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

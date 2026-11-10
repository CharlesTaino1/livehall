import SwiftUI

struct SkeletonGrid: View {
    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: Theme.Card.width, maximum: Theme.Card.width), spacing: Theme.Card.spacing)
            ],
            alignment: .leading, spacing: Theme.Spacing.medium
        ) {
            ForEach(0..<12, id: \.self) { _ in SkeletonCard() }
        }
    }
}

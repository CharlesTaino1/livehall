import SwiftUI

struct MiniPlayerResizeHandle: View {
    let width: CGFloat
    let range: ClosedRange<CGFloat>
    let resize: (CGFloat) -> Void
    let commit: () -> Void

    @State private var startWidth: CGFloat?

    var body: some View {
        Color.clear
            .frame(width: Theme.MiniPlayer.handleSize, height: Theme.MiniPlayer.handleSize)
            .contentShape(Rectangle())
            .pointerStyle(.frameResize(position: .topLeading))
            .help("拖动调整大小")
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = startWidth ?? width
                        startWidth = start
                        let horizontal = -value.translation.width
                        let vertical = -value.translation.height * Theme.MiniPlayer.aspectRatio
                        let delta = abs(horizontal) >= abs(vertical) ? horizontal : vertical
                        resize(min(max(start + delta, range.lowerBound), range.upperBound))
                    }
                    .onEnded { _ in
                        startWidth = nil
                        commit()
                    })
    }
}

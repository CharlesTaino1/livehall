import CoreGraphics

enum MultiViewGeometry {
    private static let aspectRatio: CGFloat = 16.0 / 9.0

    static func frames(layout: MultiViewLayout, maximized: Int?, in size: CGSize) -> [CGRect] {
        let gap = Theme.MultiView.gap
        let columns = 2
        let rows = layout.rows
        let tileWidth = min(
            (size.width - gap * CGFloat(columns - 1)) / CGFloat(columns),
            (size.height - gap * CGFloat(rows - 1)) / CGFloat(rows) * aspectRatio)
        let tile = CGSize(width: tileWidth, height: tileWidth / aspectRatio)
        let groupWidth = tile.width * CGFloat(columns) + gap * CGFloat(columns - 1)
        let groupHeight = tile.height * CGFloat(rows) + gap * CGFloat(rows - 1)
        let origin = CGPoint(x: (size.width - groupWidth) / 2, y: (size.height - groupHeight) / 2)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let full = fit(size)
        return (0..<layout.capacity).map { index in
            if let maximized {
                return index == maximized ? full : CGRect(origin: center, size: .zero)
            }
            return CGRect(
                x: origin.x + CGFloat(index % columns) * (tile.width + gap),
                y: origin.y + CGFloat(index / columns) * (tile.height + gap),
                width: tile.width, height: tile.height)
        }
    }

    private static func fit(_ size: CGSize) -> CGRect {
        let width = min(size.width, size.height * aspectRatio)
        let height = width / aspectRatio
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }
}

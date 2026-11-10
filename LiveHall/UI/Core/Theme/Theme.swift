import SwiftUI

enum Theme {
    enum Spacing {
        static let small: CGFloat = 8
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let page: CGFloat = 48
    }

    enum Radius {
        static let control: CGFloat = 10
        static let card: CGFloat = 8
    }

    enum Motion {
        static let controlsFade: Animation = .easeInOut(duration: 0.25)
        static let controlsIdleDelay: Duration = .seconds(3)
        static let hero: Animation = .spring(duration: 0.4, bounce: 0.05)
        static let cardExpand: Animation = .spring(duration: 0.28, bounce: 0.1)
        static let imageFade: Animation = .easeOut(duration: 0.2)
        static let hoverDelay: Duration = .milliseconds(500)
        static let layout: Animation = .spring(duration: 0.35, bounce: 0.05)
    }

    enum Card {
        static let width: CGFloat = 264
        static let aspectRatio: CGFloat = 16.0 / 9.0
        static let hoverScale: CGFloat = 1.14
        static let spacing: CGFloat = 12
        static let rowVerticalInset: CGFloat = 22
        static let offlineOpacity = 0.55
    }

    enum Sidebar {
        static let railWidth: CGFloat = 76
        static let expandedWidth: CGFloat = 208
        static let topInset: CGFloat = 56
        static let itemHeight: CGFloat = 44
    }

    enum Login {
        static let size = CGSize(width: 800, height: 560)
    }

    enum MultiView {
        static let gap: CGFloat = 2
        static let focusBorderWidth: CGFloat = 2
    }

    enum MiniPlayer {
        static let defaultWidth: CGFloat = 480
        static let minWidth: CGFloat = 280
        static let maxWindowFraction: CGFloat = 0.7
        static let handleSize: CGFloat = 28
        static let aspectRatio: CGFloat = 16.0 / 9.0
        static let margin: CGFloat = 24
    }

    enum Poster {
        static let width: CGFloat = 150
        static let aspectRatio: CGFloat = 440.0 / 610.0
    }

    enum Danmaku {
        static let laneSpacing: CGFloat = 6
        static let topInset: CGFloat = 12
        static let maxTextLength = 60
    }

    enum Player {
        static let topScrimHeight: CGFloat = 170
        static let titleFontSize: CGFloat = 26
        static let metaFontSize: CGFloat = 20
    }

    enum Color {
        static let background = SwiftUI.Color.black
        static let primaryText = SwiftUI.Color.white
        static let scrim = SwiftUI.Color.black.opacity(0.85)
        static let controlFill = SwiftUI.Color.white.opacity(0.25)
        static let secondaryText = SwiftUI.Color.white.opacity(0.7)
        static let tertiaryText = SwiftUI.Color.white.opacity(0.5)
        static let placeholder = SwiftUI.Color.white.opacity(0.08)
        static let accent = SwiftUI.Color(red: 1.0, green: 0.42, blue: 0.1)
    }
}

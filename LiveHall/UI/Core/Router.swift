import AppKit
import Observation
import SwiftUI

extension Section {
    var title: String {
        switch self {
        case .home: "首页"
        case .categories: "分区"
        case .follows: "我的关注"
        case .multiview: "多看"
        case .shortVideo: "短视频"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .categories: "square.grid.2x2"
        case .follows: "heart"
        case .multiview: "rectangle.split.2x2"
        case .shortVideo: "play.rectangle"
        }
    }
}

struct PlayRequest: Equatable {
    let roomID: RoomID
    let cardID: String
    let coverURL: URL?
}

@MainActor
@Observable
final class Router {
    private(set) var section: Section
    var path: [Route]
    private(set) var playing: PlayRequest?
    private(set) var isPlayerMinimized = false
    var miniWidth: CGFloat
    @ObservationIgnored var backHandler: (@MainActor () -> Bool)?

    var page: Page { Page(section: section, path: path) }
    var isPlayerFull: Bool { playing != nil && !isPlayerMinimized }

    init(page: Page, miniWidth: Double?) {
        section = page.section
        path = page.path
        self.miniWidth = miniWidth.map { CGFloat($0) } ?? Theme.MiniPlayer.defaultWidth
    }

    func play(_ request: PlayRequest) {
        withAnimation(Theme.Motion.hero) {
            if playing?.roomID != request.roomID { playing = request }
            isPlayerMinimized = false
        }
    }

    func minimizePlayer() {
        guard playing != nil else { return }
        withAnimation(Theme.Motion.hero) { isPlayerMinimized = true }
    }

    func expandPlayer() {
        withAnimation(Theme.Motion.hero) { isPlayerMinimized = false }
    }

    func closePlayer() {
        withAnimation(Theme.Motion.hero) {
            playing = nil
            isPlayerMinimized = false
        }
    }

    func select(_ section: Section) {
        if section == .multiview || section == .shortVideo { closePlayer() }
        self.section = section
        path = []
    }

    func showMultiView() {
        select(.multiview)
    }

    func show(_ route: Route) {
        path.append(route)
    }

    func back() {
        if isPlayerFull {
            minimizePlayer()
        } else if backHandler?() == true {
            return
        } else if !path.isEmpty {
            path.removeLast()
        } else if section != .home {
            select(.home)
        }
    }

    func escape() {
        if let window = NSApp.keyWindow, window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        } else {
            back()
        }
    }
}

import AppKit
import SwiftUI

@main
struct LiveHallApp: App {
    private let container: AppContainer

    init() {
        AppLogging.start()
        container = AppContainer()
    }

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
                .frame(minWidth: 640, minHeight: 360)
                .background(WindowChrome())
        }
        .defaultSize(width: 1280, height: 720)
        .commands {
            CommandGroup(after: .help) {
                Button("在 Finder 中显示日志") {
                    NSWorkspace.shared.activateFileViewerSelecting([AppLogging.directory])
                }
            }
            CommandGroup(after: .sidebar) {
                Button("返回") { container.router.back() }
                    .keyboardShortcut("[", modifiers: .command)
                Button("刷新") { container.refresh.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(!container.refresh.canRefresh)
                Divider()
                Button("首页") { container.router.select(.home) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("分区") { container.router.select(.categories) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("我的关注") { container.router.select(.follows) }
                    .keyboardShortcut("3", modifiers: .command)
                Button("多看") { container.router.select(.multiview) }
                    .keyboardShortcut("4", modifiers: .command)
                Button("短视频") { container.router.select(.shortVideo) }
                    .keyboardShortcut("5", modifiers: .command)
            }
        }
    }
}

import AppKit
import CocoaLumberjackSwift
import Foundation

enum AppLogging {
    static let directory = URL.libraryDirectory.appending(path: "Logs/LiveHall", directoryHint: .isDirectory)

    private static let maxFileBytes: UInt64 = 8 * 1024 * 1024
    private static let rollingInterval: TimeInterval = 24 * 60 * 60
    private static let maxFileCount: UInt = 14
    private static let diskQuotaBytes: UInt64 = 64 * 1024 * 1024

    static func start() {
        let manager = DDLogFileManagerDefault(logsDirectory: directory.path)
        manager.maximumNumberOfLogFiles = maxFileCount
        manager.logFilesDiskQuota = diskQuotaBytes
        let file = DDFileLogger(logFileManager: manager)
        file.rollingFrequency = rollingInterval
        file.maximumFileSize = maxFileBytes
        file.logFormatter = LineFormatter(includesTimestamp: true)
        DDLog.add(file)

        let console = DDOSLogger.sharedInstance
        console.logFormatter = LineFormatter(includesTimestamp: false)
        DDLog.add(console)

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil
        ) { _ in DDLog.flushLog() }

        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let system = ProcessInfo.processInfo
        AppLogger(category: "App").info(
            "启动 \(version) (\(build))，\(system.operatingSystemVersionString)，内存 \(system.physicalMemory >> 30) GB")
    }
}

private final class LineFormatter: NSObject, DDLogFormatter, @unchecked Sendable {
    private let timestampFormatter: DateFormatter?
    private let processID = ProcessInfo.processInfo.processIdentifier

    init(includesTimestamp: Bool) {
        if includesTimestamp {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
            timestampFormatter = formatter
        } else {
            timestampFormatter = nil
        }
    }

    func format(message: DDLogMessage) -> String? {
        let level =
            switch message.flag {
            case .error: "ERROR"
            case .warning: "WARN "
            default: "INFO "
            }
        let category = message.representedObject as? String ?? "-"
        let body = "\(level) [\(category)] \(message.message)"
        guard let timestampFormatter else { return body }
        return "\(timestampFormatter.string(from: message.timestamp)) \(processID) \(body)"
    }
}

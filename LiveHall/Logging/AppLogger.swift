import CocoaLumberjackSwift
import Foundation

struct LogMessage: ExpressibleByStringInterpolation, Sendable {
    let text: String

    init(stringLiteral value: String) {
        text = value
    }

    init(stringInterpolation: StringInterpolation) {
        text = stringInterpolation.text
    }

    struct StringInterpolation: StringInterpolationProtocol {
        fileprivate var text = ""

        init(literalCapacity: Int, interpolationCount: Int) {
            text.reserveCapacity(literalCapacity + interpolationCount * 8)
        }

        mutating func appendLiteral(_ literal: String) {
            text += literal
        }

        mutating func appendInterpolation(_ value: Double) {
            text += String(format: "%.3f", value)
        }

        mutating func appendInterpolation<Value>(_ value: Value) {
            text += String(describing: value)
        }
    }
}

struct AppLogger: Sendable {
    let category: String

    func info(_ message: LogMessage) {
        write(message, flag: .info)
    }

    func warning(_ message: LogMessage) {
        write(message, flag: .warning)
    }

    func error(_ message: LogMessage) {
        write(message, flag: .error)
    }

    private func write(_ message: LogMessage, flag: DDLogFlag) {
        DDLog.log(
            asynchronous: true,
            message: DDLogMessage(
                format: message.text, formatted: message.text, level: .all, flag: flag, context: 0, file: "",
                function: nil, line: 0, tag: category, options: [], timestamp: nil))
    }
}

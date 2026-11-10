import Foundation

struct StreamQuality: Sendable, Equatable, Hashable {
    let rate: Int
    let name: String
}

struct StreamLine: Sendable, Equatable, Hashable {
    let cdn: String
    let name: String
}

struct LiveStream: Sendable, Equatable {
    let request: URLRequest
    let qualities: [StreamQuality]
    let lines: [StreamLine]
    let currentRate: Int
    let currentCDN: String
}

enum StreamTier: Sendable {
    case economy
    case high

    func rate(on platform: Platform) -> Int {
        switch (platform, self) {
        case (.douyu, .economy): 2
        case (.douyu, .high): 3
        case (.douyin, .economy): 1
        case (.douyin, .high): 3
        }
    }
}

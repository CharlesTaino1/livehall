import Foundation

enum PlaybackState: Sendable, Equatable {
    case idle
    case connecting
    case playing
    case buffering
    case reconnecting(networkDown: Bool)
    case ended
    case failed(PlaybackFailure)
}

enum PlaybackFailure: Sendable, Equatable {
    case unsupportedCodec
    case unrecoverable
}

enum StreamLocatingError: Error, Sendable {
    case offline
    case networkDown
    case failed
}

typealias StreamLocator = @Sendable (_ failures: Int) async throws(StreamLocatingError) -> URLRequest

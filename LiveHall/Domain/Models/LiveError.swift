enum LiveError: Error, Sendable, Equatable {
    case roomNotFound
    case notLive
    case networkDown
    case network(String)
    case badResponse(String)
    case signFailed(String)
}

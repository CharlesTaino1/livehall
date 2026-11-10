import Foundation

struct HTTPClient: Sendable {
    private static let retryDelay = Duration.milliseconds(400)

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        session = URLSession(configuration: configuration)
    }

    func data(for request: URLRequest) async throws(LiveError) -> Data {
        do throws(LiveError) {
            return try await dataOnce(for: request)
        } catch {
            switch error {
            case .networkDown, .network:
                try? await Task.sleep(for: Self.retryDelay)
                guard !Task.isCancelled else { throw error }
                return try await dataOnce(for: request)
            case .roomNotFound, .notLive, .badResponse, .signFailed:
                throw error
            }
        }
    }

    func response(for request: URLRequest) async throws(LiveError) -> HTTPURLResponse {
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw LiveError.badResponse("不是 HTTP 应答") }
            return http
        } catch let error as LiveError {
            throw error
        } catch {
            throw Self.map(error)
        }
    }

    private func dataOnce(for request: URLRequest) async throws(LiveError) -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw LiveError.badResponse("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            }
            return data
        } catch let error as LiveError {
            throw error
        } catch {
            throw Self.map(error)
        }
    }

    private static func map(_ error: Error) -> LiveError {
        guard let error = error as? URLError else { return .network(error.localizedDescription) }
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .cannotFindHost,
            .cannotConnectToHost, .dnsLookupFailed, .timedOut, .internationalRoamingOff:
            return .networkDown
        default:
            return .network(error.localizedDescription)
        }
    }
}

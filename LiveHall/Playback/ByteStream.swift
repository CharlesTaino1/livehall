import Foundation

enum ByteStreamError: Error, Sendable {
    case status(Int)
    case network(URLError.Code)
}

final class ByteStream: Sendable {
    let chunks: AsyncThrowingStream<Data, any Error>
    private let session: URLSession
    private let task: URLSessionDataTask

    init(request: URLRequest) {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: Data.self, throwing: (any Error).self)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: Delegate(continuation), delegateQueue: nil)
        task = session.dataTask(with: request)
        chunks = stream
        task.resume()
    }

    func cancel() {
        task.cancel()
        session.invalidateAndCancel()
    }

    private final class Delegate: NSObject, URLSessionDataDelegate, Sendable {
        private let continuation: AsyncThrowingStream<Data, any Error>.Continuation

        init(_ continuation: AsyncThrowingStream<Data, any Error>.Continuation) {
            self.continuation = continuation
        }

        func urlSession(
            _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse
        ) async -> URLSession.ResponseDisposition {
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                continuation.finish(throwing: ByteStreamError.status(http.statusCode))
                return .cancel
            }
            return .allow
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            continuation.yield(data)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
            if let error = error as? URLError {
                if error.code == .cancelled {
                    continuation.finish()
                } else {
                    continuation.finish(throwing: ByteStreamError.network(error.code))
                }
            } else if let error {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
            session.finishTasksAndInvalidate()
        }
    }
}

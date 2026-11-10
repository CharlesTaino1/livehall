import Foundation

struct DouyinSession: Sendable, Equatable, Hashable, Codable {
    let cookies: [String: String]

    var verifyFingerprint: String? { cookies["s_v_web_id"] }

    var cookieHeader: String {
        cookies.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
    }
}

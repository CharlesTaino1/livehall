import Foundation

struct DouyuSession: Sendable, Equatable, Hashable, Codable {
    let cookies: [String: String]

    var nickname: String {
        guard let raw = cookies["acf_nickname"], !raw.isEmpty else { return "已登录" }
        return raw.removingPercentEncoding ?? raw
    }

    var deviceID: String? { cookies["dy_did"] }

    var cookieHeader: String {
        cookies.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
    }
}

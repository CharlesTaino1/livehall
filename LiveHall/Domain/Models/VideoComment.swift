import Foundation

struct VideoComment: Sendable, Equatable, Hashable, Identifiable {
    let id: String
    let text: String
    let authorName: String
    let avatarURL: URL?
    let likeCount: Int
    let replyCount: Int
    let createdAt: Date?
    let region: String
}

struct CommentPage: Sendable, Equatable {
    let comments: [VideoComment]
    let nextCursor: Int?
    let total: Int
}

import Foundation

struct ShortVideo: Sendable, Equatable, Hashable, Identifiable {
    let id: String
    let description: String
    let authorName: String
    let avatarURL: URL?
    let coverURL: URL?
    let playURL: URL
    let aspectRatio: Double
    let likeCount: Int
    let commentCount: Int
}

import Foundation

struct LenientInt: Decodable {
    let value: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Int.self) {
            value = number
        } else {
            value = Int(try container.decode(String.self)) ?? 0
        }
    }
}

struct DouyinImage: Decodable {
    let urlList: [String]

    var url: URL? { urlList.first.flatMap { URL(string: $0) } }

    enum CodingKeys: String, CodingKey {
        case urlList = "url_list"
    }
}

struct DouyinRoom: Decodable {
    struct Owner: Decodable {
        let nickname: String?
        let avatarThumb: DouyinImage?

        enum CodingKeys: String, CodingKey {
            case nickname
            case avatarThumb = "avatar_thumb"
        }
    }

    struct ViewStats: Decodable {
        let displayValue: LenientInt?

        enum CodingKeys: String, CodingKey {
            case displayValue = "display_value"
        }
    }

    struct GameData: Decodable {
        struct Tag: Decodable {
            let name: String?

            enum CodingKeys: String, CodingKey {
                case name = "game_tag_name"
            }
        }
        let tag: Tag?

        enum CodingKeys: String, CodingKey {
            case tag = "game_tag_info"
        }
    }

    struct StreamURL: Decodable {
        struct CoreData: Decodable {
            struct PullData: Decodable {
                struct Options: Decodable {
                    struct Quality: Decodable {
                        let name: String
                        let key: String

                        enum CodingKeys: String, CodingKey {
                            case name
                            case key = "sdk_key"
                        }
                    }
                    struct Default: Decodable {
                        let key: String

                        enum CodingKeys: String, CodingKey {
                            case key = "sdk_key"
                        }
                    }
                    let qualities: [Quality]?
                    let defaultQuality: Default?

                    enum CodingKeys: String, CodingKey {
                        case qualities
                        case defaultQuality = "default_quality"
                    }
                }
                let options: Options?
                let streamData: String?

                enum CodingKeys: String, CodingKey {
                    case options
                    case streamData = "stream_data"
                }
            }
            let pullData: PullData?

            enum CodingKeys: String, CodingKey {
                case pullData = "pull_data"
            }
        }
        let orientation: Int?
        let coreData: CoreData?

        enum CodingKeys: String, CodingKey {
            case orientation = "stream_orientation"
            case coreData = "live_core_sdk_data"
        }
    }

    let roomID: String
    let status: Int?
    let title: String?
    let owner: Owner?
    let cover: DouyinImage?
    let viewStats: ViewStats?
    let gameData: GameData?
    let streamURL: StreamURL?

    var isPortrait: Bool { streamURL?.orientation == 1 }
    var popularity: Int { viewStats?.displayValue?.value ?? 0 }

    enum CodingKeys: String, CodingKey {
        case roomID = "id_str"
        case status
        case title
        case owner
        case cover
        case viewStats = "room_view_stats"
        case gameData = "game_data"
        case streamURL = "stream_url"
    }
}

struct DouyinListEnvelope: Decodable {
    struct Item: Decodable {
        let webRid: String
        let tagName: String?
        let room: DouyinRoom

        enum CodingKeys: String, CodingKey {
            case webRid = "web_rid"
            case tagName = "tag_name"
            case room
        }
    }
    struct Payload: Decodable {
        let data: [Item]
    }
    let data: Payload
}

struct DouyinEnterEnvelope: Decodable {
    struct User: Decodable {
        let nickname: String?
        let avatarThumb: DouyinImage?

        enum CodingKeys: String, CodingKey {
            case nickname
            case avatarThumb = "avatar_thumb"
        }
    }
    struct Payload: Decodable {
        let data: [DouyinRoom]
        let user: User?
    }
    let data: Payload
}

struct DouyinStreamData: Decodable {
    struct Line: Decodable {
        let flv: String?
    }
    struct Entry: Decodable {
        let main: Line?
        let backup: Line?
    }
    let data: [String: Entry]
}

struct DouyinFeedEnvelope: Decodable {
    let awemeList: [DouyinFeedItem]?

    enum CodingKeys: String, CodingKey {
        case awemeList = "aweme_list"
    }
}

struct DouyinFeedItem: Decodable {
    struct Author: Decodable {
        let nickname: String?
        let avatarThumb: DouyinImage?

        enum CodingKeys: String, CodingKey {
            case nickname
            case avatarThumb = "avatar_thumb"
        }
    }

    struct Video: Decodable {
        struct PlayAddress: Decodable {
            let urlList: [String]

            enum CodingKeys: String, CodingKey {
                case urlList = "url_list"
            }
        }
        let playAddress: PlayAddress?
        let cover: DouyinImage?
        let width: Int?
        let height: Int?

        enum CodingKeys: String, CodingKey {
            case playAddress = "play_addr"
            case cover
            case width
            case height
        }
    }

    struct Statistics: Decodable {
        let diggCount: Int?
        let commentCount: Int?

        enum CodingKeys: String, CodingKey {
            case diggCount = "digg_count"
            case commentCount = "comment_count"
        }
    }

    let id: String
    let type: Int?
    let description: String?
    let author: Author?
    let video: Video?
    let statistics: Statistics?
    let isAds: Bool?

    enum CodingKeys: String, CodingKey {
        case id = "aweme_id"
        case type = "aweme_type"
        case description = "desc"
        case author
        case video
        case statistics
        case isAds = "is_ads"
    }
}

struct DouyinCommentEnvelope: Decodable {
    struct Item: Decodable {
        struct User: Decodable {
            let nickname: String?
            let avatarThumb: DouyinImage?

            enum CodingKeys: String, CodingKey {
                case nickname
                case avatarThumb = "avatar_thumb"
            }
        }

        let id: String
        let text: String?
        let user: User?
        let likeCount: Int?
        let replyCount: Int?
        let createTime: Int?
        let region: String?

        enum CodingKeys: String, CodingKey {
            case id = "cid"
            case text
            case user
            case likeCount = "digg_count"
            case replyCount = "reply_comment_total"
            case createTime = "create_time"
            case region = "ip_label"
        }
    }

    let comments: [Item]?
    let cursor: Int?
    let hasMore: Int?
    let total: Int?

    enum CodingKeys: String, CodingKey {
        case comments
        case cursor
        case hasMore = "has_more"
        case total
    }
}

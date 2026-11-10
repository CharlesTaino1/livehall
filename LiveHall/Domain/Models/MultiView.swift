enum MultiViewLayout: String, Sendable, Equatable, Codable, CaseIterable {
    case pair
    case quad

    var capacity: Int {
        switch self {
        case .pair: 2
        case .quad: 4
        }
    }

    var rows: Int {
        switch self {
        case .pair: 1
        case .quad: 2
        }
    }

    var streamTier: StreamTier {
        switch self {
        case .pair: .high
        case .quad: .economy
        }
    }
}

struct MultiViewState: Sendable, Equatable, Codable {
    static let maxRooms = 4

    var layout = MultiViewLayout.quad
    var roomIDs: [RoomID] = []
}

import SwiftUI

struct RoomGrid: View {
    let rooms: [RoomSummary]
    let rowID: String
    var onRoomAppear: ((RoomSummary) -> Void)?

    @Environment(PreviewModel.self) private var preview
    @State private var columns = 1

    var body: some View {
        LazyVStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            ForEach(chunks) { chunk in
                HStack(spacing: Theme.Card.spacing) {
                    ForEach(chunk.rooms) { room in
                        RoomCard(room: room, rowID: rowID)
                            .onAppear { onRoomAppear?(room) }
                    }
                }
                .zIndex(hasExpandedCard(in: chunk) ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: Int.self) { proxy in
            max(1, Int((proxy.size.width + Theme.Card.spacing) / (Theme.Card.width + Theme.Card.spacing)))
        } action: { newColumns in
            columns = newColumns
        }
    }

    private func hasExpandedCard(in chunk: Chunk) -> Bool {
        chunk.rooms.contains { preview.expandedCardID == "\(rowID)-\($0.id)" }
    }

    private var chunks: [Chunk] {
        stride(from: 0, to: rooms.count, by: columns).map { start in
            Chunk(rooms: Array(rooms[start..<min(start + columns, rooms.count)]))
        }
    }

    private struct Chunk: Identifiable {
        let rooms: [RoomSummary]
        var id: RoomID { rooms[0].id }
    }
}

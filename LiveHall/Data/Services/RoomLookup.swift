enum RoomLookup {
    static let maxConcurrent = 8

    static func summaries(
        of ids: [Int], fetch: @escaping @Sendable (Int) async -> Result<RoomSummary, LiveError>
    ) async throws(LiveError) -> [RoomSummary] {
        guard !ids.isEmpty else { return [] }
        var found: [Int: RoomSummary] = [:]
        var networkFailures = 0
        await withTaskGroup(of: (Int, Result<RoomSummary, LiveError>).self) { group in
            var iterator = ids.makeIterator()
            func next() {
                guard let id = iterator.next() else { return }
                group.addTask { (id, await fetch(id)) }
            }
            for _ in 0..<maxConcurrent { next() }
            while let (id, result) = await group.next() {
                switch result {
                case .success(let summary): found[id] = summary
                case .failure(.networkDown): networkFailures += 1
                case .failure: break
                }
                next()
            }
        }
        if found.isEmpty && networkFailures > 0 { throw .networkDown }
        return ids.compactMap { found[$0] }
    }
}

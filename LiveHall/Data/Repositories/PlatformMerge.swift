import Foundation

enum PlatformMerge {
    static func gather<T: Sendable>(
        count: Int, fetch: @escaping @Sendable (Int) async throws(LiveError) -> T
    ) async throws(LiveError) -> [T] {
        let results = await withTaskGroup(of: (Int, Result<T, LiveError>).self) { group in
            for index in 0..<count {
                group.addTask {
                    do throws(LiveError) {
                        return (index, .success(try await fetch(index)))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            var collected: [(Int, Result<T, LiveError>)] = []
            for await item in group { collected.append(item) }
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }
        var values: [T] = []
        var firstError: LiveError?
        for result in results {
            switch result {
            case .success(let value): values.append(value)
            case .failure(let error): firstError = firstError ?? error
            }
        }
        if values.isEmpty, let firstError { throw firstError }
        return values
    }

    static func interleave(_ lists: [[RoomSummary]]) -> [RoomSummary] {
        var merged: [RoomSummary] = []
        var seen: Set<RoomID> = []
        for index in 0..<(lists.map(\.count).max() ?? 0) {
            for list in lists where index < list.count && seen.insert(list[index].id).inserted {
                merged.append(list[index])
            }
        }
        return merged
    }

    static func groups(_ lists: [[CategoryGroup]]) -> [CategoryGroup] {
        var groupNames: [String] = []
        var members: [String: [LiveCategory]] = [:]
        var owner: [String: String] = [:]
        for list in lists {
            for group in list {
                if members[group.name] == nil { groupNames.append(group.name) }
                for category in group.categories {
                    if let home = owner[category.name],
                        let index = members[home]?.firstIndex(where: { $0.name == category.name }),
                        let existing = members[home]?[index]
                    {
                        members[home]?[index] = combine(existing, category)
                    } else {
                        members[group.name, default: []].append(category)
                        owner[category.name] = group.name
                    }
                }
            }
        }
        return groupNames.compactMap { name in
            guard let categories = members[name], !categories.isEmpty else { return nil }
            let ordered = categories.enumerated()
                .sorted { ($0.element.liveCount ?? 0, $1.offset) > ($1.element.liveCount ?? 0, $0.offset) }
                .map(\.element)
            return CategoryGroup(name: name, categories: ordered)
        }
    }

    private static func combine(_ first: LiveCategory, _ second: LiveCategory) -> LiveCategory {
        let counts = [first.liveCount, second.liveCount].compactMap { $0 }
        return LiveCategory(
            name: first.name, sources: first.sources + second.sources,
            liveCount: counts.isEmpty ? nil : counts.reduce(0, +), posterURL: first.posterURL ?? second.posterURL)
    }
}

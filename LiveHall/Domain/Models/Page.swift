enum Section: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    case home
    case categories
    case follows
    case multiview
    case shortVideo

    var id: Self { self }
}

enum Route: Sendable, Hashable, Codable {
    case category(LiveCategory)
}

struct Page: Sendable, Equatable, Codable {
    var section = Section.home
    var path: [Route] = []

    init(section: Section = .home, path: [Route] = []) {
        self.section = section
        self.path = path
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        section = try container.decode(Section.self, forKey: .section)
        path = (try? container.decode([Route].self, forKey: .path)) ?? []
    }
}

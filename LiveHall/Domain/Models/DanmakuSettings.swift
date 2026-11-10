struct DanmakuSettings: Sendable, Equatable, Codable {
    enum FontSize: String, Sendable, Codable, CaseIterable {
        case small, medium, large
    }

    enum Area: String, Sendable, Codable, CaseIterable {
        case full, half, third
    }

    enum Density: String, Sendable, Codable, CaseIterable {
        case sparse, normal, dense
    }

    enum Typeface: String, Sendable, Codable, CaseIterable {
        case system, heiti, rounded, kai, song
    }

    enum Style: String, Sendable, Codable, CaseIterable {
        case outline, shadow, plain
    }

    enum Weight: String, Sendable, Codable, CaseIterable {
        case light, regular, bold
    }

    var weight = Weight.regular
    var style = Style.outline
    var edgeWidth = 2.0
    var speed = 200.0
    var typeface = Typeface.system
    var fontSize = FontSize.medium
    var opacity = 0.9
    var area = Area.half
    var density = Density.normal
    var blockedWords: [String] = []

    func isBlocked(_ text: String) -> Bool {
        blockedWords.contains { text.contains($0) }
    }
}

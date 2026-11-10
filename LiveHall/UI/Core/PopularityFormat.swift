func formatPopularity(_ value: Int) -> String {
    func scaled(_ unit: Double, _ suffix: String) -> String {
        let text = String(format: "%.1f", (Double(value) / unit * 10).rounded(.down) / 10)
        return (text.hasSuffix(".0") ? String(text.dropLast(2)) : text) + suffix
    }
    switch value {
    case ..<10_000: return String(value)
    case ..<100_000_000: return scaled(10_000, "万")
    default: return scaled(100_000_000, "亿")
    }
}

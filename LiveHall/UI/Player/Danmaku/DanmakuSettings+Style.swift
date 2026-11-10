import AppKit

extension DanmakuSettings.FontSize {
    var points: CGFloat {
        switch self {
        case .small: 20
        case .medium: 25
        case .large: 32
        }
    }

    var title: String {
        switch self {
        case .small: "小"
        case .medium: "中"
        case .large: "大"
        }
    }
}

extension DanmakuSettings.Area {
    var fraction: CGFloat {
        switch self {
        case .full: 1
        case .half: 0.5
        case .third: 1.0 / 3.0
        }
    }

    var title: String {
        switch self {
        case .full: "全屏"
        case .half: "上半"
        case .third: "上三分之一"
        }
    }
}

extension DanmakuSettings.Density {
    var gap: CGFloat {
        switch self {
        case .sparse: 200
        case .normal: 40
        case .dense: 8
        }
    }

    var title: String {
        switch self {
        case .sparse: "稀疏"
        case .normal: "适中"
        case .dense: "密集"
        }
    }
}

extension DanmakuSettings.Typeface {
    var title: String {
        switch self {
        case .system: "系统"
        case .heiti: "黑体"
        case .rounded: "圆体"
        case .kai: "楷体"
        case .song: "宋体"
        }
    }

    func font(size: CGFloat, weight: DanmakuSettings.Weight) -> NSFont {
        let name: String? =
            switch self {
            case .system: nil
            case .heiti: "Heiti SC"
            case .rounded: "Yuanti SC"
            case .kai: "Kaiti SC"
            case .song: "Songti SC"
            }
        guard let name, let base = NSFont(name: name, size: size) else {
            return .systemFont(ofSize: size, weight: weight.systemWeight)
        }
        return weight == .bold ? NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask) : base
    }
}

extension DanmakuSettings.Style {
    var title: String {
        switch self {
        case .outline: "描边"
        case .shadow: "投影"
        case .plain: "无"
        }
    }
}

extension DanmakuSettings.Weight {
    var systemWeight: NSFont.Weight {
        switch self {
        case .light: .light
        case .regular: .regular
        case .bold: .semibold
        }
    }

    var title: String {
        switch self {
        case .light: "细"
        case .regular: "常规"
        case .bold: "粗"
        }
    }
}

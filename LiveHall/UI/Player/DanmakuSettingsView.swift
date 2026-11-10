import SwiftUI

struct DanmakuSettingsView: View {
    @Binding var settings: DanmakuSettings

    @State private var blockedText: String

    init(settings: Binding<DanmakuSettings>) {
        _settings = settings
        _blockedText = State(initialValue: settings.wrappedValue.blockedWords.joined(separator: " "))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            SettingRow("字体") {
                Picker("字体", selection: $settings.typeface) {
                    ForEach(DanmakuSettings.Typeface.allCases, id: \.self) { Text($0.title) }
                }
                .pickerStyle(.menu)
            }
            SettingRow("字重") {
                Picker("字重", selection: $settings.weight) {
                    ForEach(DanmakuSettings.Weight.allCases, id: \.self) { Text($0.title) }
                }
            }
            SettingRow("字号") {
                Picker("字号", selection: $settings.fontSize) {
                    ForEach(DanmakuSettings.FontSize.allCases, id: \.self) { Text($0.title) }
                }
            }
            SettingRow("样式") {
                Picker("样式", selection: $settings.style) {
                    ForEach(DanmakuSettings.Style.allCases, id: \.self) { Text($0.title) }
                }
            }
            SettingRow("边缘粗细") {
                Slider(value: $settings.edgeWidth, in: 0.5...6)
                    .disabled(settings.style == .plain)
            }
            SettingRow("透明度") {
                Slider(value: $settings.opacity, in: 0.2...1)
            }
            SettingRow("滚动速度") {
                Slider(value: $settings.speed, in: 100...400)
            }
            SettingRow("显示区域") {
                Picker("显示区域", selection: $settings.area) {
                    ForEach(DanmakuSettings.Area.allCases, id: \.self) { Text($0.title) }
                }
            }
            SettingRow("密度") {
                Picker("密度", selection: $settings.density) {
                    ForEach(DanmakuSettings.Density.allCases, id: \.self) { Text($0.title) }
                }
            }
            SettingRow("屏蔽词") {
                TextField("用空格分隔", text: $blockedText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: blockedText) { _, text in
                        settings.blockedWords = text.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(
                            String.init)
                    }
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(Theme.Spacing.medium)
        .frame(width: 300)
    }
}

private struct SettingRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small / 2) {
            Text(title).font(.caption).foregroundStyle(Theme.Color.secondaryText)
            content
        }
    }
}

import SwiftUI

struct RoomPickerView: View {
    let excluding: Set<RoomID>
    let pick: (RoomID) -> Void

    @State private var model: RoomPickerViewModel
    @State private var roomText = ""
    @State private var roomPlatform = Platform.douyu

    init(model: RoomPickerViewModel, excluding: Set<RoomID>, pick: @escaping (RoomID) -> Void) {
        _model = State(initialValue: model)
        self.excluding = excluding
        self.pick = pick
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            HStack(spacing: Theme.Spacing.small) {
                Picker("平台", selection: $roomPlatform) {
                    ForEach(Platform.allCases) { Text($0.name).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                TextField("输入房间号，回车添加", text: $roomText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        guard let id = Int(roomText.trimmingCharacters(in: .whitespaces)), id > 0 else { return }
                        pick(RoomID(roomPlatform, id))
                    }
            }
            content
        }
        .padding(Theme.Spacing.medium)
        .frame(width: 380, height: 460)
        .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let offline):
            VStack(spacing: Theme.Spacing.medium) {
                Text(offline ? "网络不可用，请检查连接" : "加载失败，请重试").foregroundStyle(Theme.Color.secondaryText)
                Button("重试") { Task { await model.load() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .content(let sections):
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.medium, pinnedViews: []) {
                    group("关注中", sections.following)
                    group("最近看过", sections.recents)
                    group("热门推荐", sections.popular)
                }
            }
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ rooms: [RoomSummary]) -> some View {
        let shown = rooms.filter { !excluding.contains($0.id) }
        if !shown.isEmpty {
            Text(title).font(.headline)
            ForEach(shown) { room in
                PickerRow(room: room) { pick(room.id) }
            }
        }
    }
}

private struct PickerRow: View {
    let room: RoomSummary
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.small + 4) {
                CoverImage(url: room.coverURL, size: CGSize(width: 96, height: 54))
                    .frame(width: 96, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
                    .overlay(alignment: .topLeading) { SourceTag(platform: room.id.platform).padding(3) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(room.title).font(.callout.weight(.semibold)).lineLimit(1)
                    Text("\(room.anchorName) · \(formatPopularity(room.popularity))")
                        .font(.caption)
                        .foregroundStyle(Theme.Color.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(4)
            .background(.white.opacity(isHovering ? 0.1 : 0), in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

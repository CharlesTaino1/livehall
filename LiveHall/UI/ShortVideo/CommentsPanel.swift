import SwiftUI

struct CommentsPanel: View {
    let model: CommentsViewModel
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.total > 0 ? "评论 \(formatPopularity(model.total))" : "评论").font(.headline)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .help("关闭评论（C）")
                .accessibilityLabel("关闭评论")
            }
            .padding(Theme.Spacing.medium)
            Divider()
            content
        }
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            VStack(spacing: Theme.Spacing.medium) {
                ForEach(0..<6, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Theme.Radius.card)
                        .fill(Theme.Color.placeholder)
                        .frame(height: 56)
                }
                Spacer()
            }
            .padding(Theme.Spacing.medium)
        case .failed(let offline):
            StatusMessage(
                symbol: offline ? "wifi.slash" : "exclamationmark.triangle",
                message: offline ? "网络不可用，请检查连接" : "评论加载失败", actionTitle: "重试"
            ) {
                Task { await model.load() }
            }
            .frame(maxHeight: .infinity)
        case .content:
            if model.comments.isEmpty {
                Text("还没有评论")
                    .foregroundStyle(Theme.Color.secondaryText)
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                        ForEach(model.comments) { comment in
                            CommentRow(comment: comment)
                        }
                        footer
                    }
                    .padding(Theme.Spacing.medium)
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if model.isLoadMoreFailed {
            Button("加载失败，点这里重试") { Task { await model.loadMore() } }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Color.secondaryText)
                .frame(maxWidth: .infinity)
        } else if model.hasMore {
            ProgressView().controlSize(.small)
                .frame(maxWidth: .infinity)
                .task { await model.loadMore() }
        }
    }
}

private struct CommentRow: View {
    private static let avatarSize: CGFloat = 32
    private static let timeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter
    }()

    let comment: VideoComment

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.small) {
            CoverImage(url: comment.avatarURL, size: CGSize(width: Self.avatarSize, height: Self.avatarSize))
                .frame(width: Self.avatarSize, height: Self.avatarSize)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(comment.authorName).font(.subheadline).foregroundStyle(Theme.Color.secondaryText)
                Text(comment.text).font(.callout).textSelection(.enabled)
                HStack(spacing: Theme.Spacing.small) {
                    Text(meta).font(.caption).foregroundStyle(Theme.Color.tertiaryText)
                    Spacer()
                    if comment.replyCount > 0 {
                        Text("\(comment.replyCount) 条回复").font(.caption).foregroundStyle(Theme.Color.tertiaryText)
                    }
                    Label(formatPopularity(comment.likeCount), systemImage: "heart")
                        .font(.caption)
                        .foregroundStyle(Theme.Color.tertiaryText)
                }
            }
        }
    }

    private var meta: String {
        let time = comment.createdAt.map { Self.timeFormatter.localizedString(for: $0, relativeTo: .now) }
        return [time, comment.region.isEmpty ? nil : comment.region].compactMap { $0 }.joined(separator: " · ")
    }
}

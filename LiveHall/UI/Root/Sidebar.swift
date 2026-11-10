import SwiftUI

struct Sidebar: View {
    @Environment(Router.self) private var router
    @Environment(\.controlActiveState) private var activeState
    @State private var isHovering = false

    private var isExpanded: Bool { isHovering && activeState != .inactive }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Section.allCases) { section in
                SidebarItem(section: section, isSelected: router.section == section, isExpanded: isExpanded)
            }
            Spacer()
            AccountItem(platform: .douyu, isExpanded: isExpanded)
            AccountItem(platform: .douyin, isExpanded: isExpanded)
        }
        .padding(.top, Theme.Sidebar.topInset)
        .padding(.bottom, Theme.Spacing.medium)
        .padding(.horizontal, Theme.Spacing.small)
        .frame(width: isExpanded ? Theme.Sidebar.expandedWidth : Theme.Sidebar.railWidth, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background {
            if isExpanded {
                Rectangle().fill(.regularMaterial).ignoresSafeArea()
            } else {
                Theme.Color.background.ignoresSafeArea()
            }
        }
        .onHover { isHovering = $0 }
        .onChange(of: activeState) { _, state in
            if state == .inactive { isHovering = false }
        }
    }
}

private struct SidebarItem: View {
    let section: Section
    let isSelected: Bool
    let isExpanded: Bool

    @Environment(Router.self) private var router
    @Environment(RefreshCenter.self) private var refresh
    @Environment(\.controlActiveState) private var activeState
    @State private var isHovering = false

    private var isHighlighted: Bool { isHovering && activeState != .inactive }

    var body: some View {
        Button {
            if isSelected, router.path.isEmpty {
                refresh.refresh()
            } else {
                router.select(section)
            }
        } label: {
            HStack(spacing: Theme.Spacing.medium) {
                Image(systemName: isSelected ? "\(section.symbol).fill" : section.symbol)
                    .font(.title3)
                    .frame(width: 28)
                if isExpanded {
                    Text(section.title)
                        .font(.body.weight(isSelected ? .semibold : .regular))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.small + 4)
            .frame(height: Theme.Sidebar.itemHeight)
            .foregroundStyle(isSelected ? .white : Theme.Color.secondaryText)
            .background(
                .white.opacity(isHighlighted ? 0.12 : 0),
                in: RoundedRectangle(cornerRadius: Theme.Radius.control)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .onChange(of: activeState) { _, state in
            if state == .inactive { isHovering = false }
        }
        .help(section.title)
        .accessibilityLabel(section.title)
    }
}

private struct AccountItem: View {
    let platform: Platform
    let isExpanded: Bool

    @Environment(AccountViewModel.self) private var account
    @Environment(\.controlActiveState) private var activeState
    @State private var isHovering = false
    @State private var isConfirmingSignOut = false

    private var isHighlighted: Bool { isHovering && activeState != .inactive }

    private var isSignedIn: Bool {
        switch platform {
        case .douyu: account.session != nil
        case .douyin: account.douyinSession != nil
        }
    }

    private var title: String {
        switch platform {
        case .douyu: account.session?.nickname ?? "登录斗鱼"
        case .douyin: isSignedIn ? "已登录抖音" : "登录抖音"
        }
    }

    private var symbol: String {
        switch platform {
        case .douyu: isSignedIn ? "person.crop.circle.fill" : "person.crop.circle"
        case .douyin: isSignedIn ? "music.note.tv.fill" : "music.note.tv"
        }
    }

    private var signInHelp: String {
        switch platform {
        case .douyu: "登录斗鱼，解锁蓝光 8M 和原画"
        case .douyin: "登录抖音，短视频按你的账号推荐"
        }
    }

    var body: some View {
        Button {
            if isSignedIn {
                isConfirmingSignOut = true
            } else {
                account.beginLogin(platform)
            }
        } label: {
            HStack(spacing: Theme.Spacing.medium) {
                Image(systemName: symbol)
                    .font(.title3)
                    .frame(width: 28)
                if isExpanded {
                    Text(title)
                        .font(.body)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.small + 4)
            .frame(height: Theme.Sidebar.itemHeight)
            .foregroundStyle(isSignedIn ? .white : Theme.Color.secondaryText)
            .background(
                .white.opacity(isHighlighted ? 0.12 : 0),
                in: RoundedRectangle(cornerRadius: Theme.Radius.control)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .onChange(of: activeState) { _, state in
            if state == .inactive { isHovering = false }
        }
        .help(isSignedIn ? "已登录：\(title)" : signInHelp)
        .accessibilityLabel(title)
        .confirmationDialog("退出\(platform.name)登录？", isPresented: $isConfirmingSignOut) {
            Button("退出登录", role: .destructive) { account.signOut(platform) }
            Button("取消", role: .cancel) {}
        }
    }
}

import SwiftUI

/// Figma 41:644 / 41:710: global navigation and local history in one drawer.
struct ConversationNavigationMenu: View {
    let sessions: [ConversationSession]
    let selectedSessionID: String?
    let onSelect: (String) -> Void
    let onNewConversation: () -> Void
    let onSettings: () -> Void
    let onStatistics: () -> Void
    let onDismiss: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var isTitleFocused: Bool
    @ScaledMetric(relativeTo: .title) private var brandSize: CGFloat = 29
    @ScaledMetric(relativeTo: .headline) private var actionSize: CGFloat = 19
    @ScaledMetric(relativeTo: .body) private var rowSize: CGFloat = 18
    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 12
    private typealias Palette = XiaoLiaoTheme.NavigationMenu

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Button(action: onDismiss) {
                    XiaoLiaoTheme.historyScrim.opacity(0.69)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭菜单")
                .accessibilityIdentifier("menu.scrim")

                HStack(alignment: .top, spacing: 12) {
                    panel(compact: geometry.size.height < 620 || dynamicTypeSize.isAccessibilitySize)
                        .frame(width: min(352, max(0, geometry.size.width - 88)))
                        .frame(maxHeight: .infinity)

                    NavigationMenuButton(isExpanded: true, action: onDismiss)
                        .padding(.top, 12)
                    Spacer(minLength: 0)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape, onDismiss)
        .accessibilityIdentifier("menu.drawer")
        .onAppear { isTitleFocused = true }
    }

    private func panel(compact: Bool) -> some View {
        VStack(spacing: 0) {
            if compact {
                // Let the header scroll too on short screens or very large type.
                // This keeps every destination reachable in landscape.
                List {
                    menuHeader.menuListRow(insets: .init())
                    historyHeading.menuListRow(insets: .init())
                    historyRows
                    footer.menuListRow(insets: .init())
                }
                .menuListStyle()
            } else {
                menuHeader
                historyHeading
                List { historyRows }
                    .menuListStyle()
                    .accessibilityIdentifier("menu.history")
                footer
            }
        }
        .foregroundStyle(Palette.text)
        .background {
            Palette.background
                .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 24, topTrailingRadius: 24))
                .ignoresSafeArea(edges: .vertical)
        }
    }

    private var menuHeader: some View {
        VStack(spacing: 20) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("小聊")
                        .font(.system(size: brandSize, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($isTitleFocused)
                    Text("你的英语学习伙伴")
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onSettings) {
                    // User-approved monochrome replacement for Figma's gear emoji.
                    Image(systemName: "gearshape")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                        .background(Palette.control, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("对话设置")
                .accessibilityIdentifier("menu.settings")
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 12)

            Button(action: onNewConversation) {
                HStack(spacing: 16) {
                    Text("＋").font(.title)
                        .accessibilityHidden(true)
                    Text("开始新对话")
                        .font(.system(size: actionSize, weight: .bold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, minHeight: 66)
                .background(Palette.newConversation, in: RoundedRectangle(cornerRadius: 17))
                .contentShape(RoundedRectangle(cornerRadius: 17))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("menu.new")

            Button(action: onStatistics) {
                HStack(spacing: 14) {
                    Text("▤").font(.title)
                        .foregroundStyle(Palette.progressGlyph)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 14) {
                        Text("学习进度")
                            .font(.system(size: actionSize, weight: .bold))
                        Text("看看你的英语进步")
                            .font(.footnote)
                            .foregroundStyle(Palette.progressSubtitle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text("›").font(.title)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 17)
                .frame(maxWidth: .infinity, minHeight: 100)
                .background(Palette.progress, in: RoundedRectangle(cornerRadius: 17))
                .contentShape(RoundedRectangle(cornerRadius: 17))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("学习进度，全部对话的学习统计")
            .accessibilityIdentifier("menu.statistics")
        }
        .padding(.horizontal, 20)
        .padding(.top, 32)
    }

    private var historyHeading: some View {
        VStack(spacing: 18) {
            HStack {
                Text("以前的对话").font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text("最近").font(.system(size: captionSize))
                    .foregroundStyle(Palette.secondary)
            }
            Rectangle().fill(Palette.divider).frame(height: 1)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 24)
        .padding(.top, 30)
        .padding(.bottom, 13)
    }

    private var historyRows: some View {
        ForEach(sessions) { session in
            historyRow(session)
                .menuListRow(insets: EdgeInsets(top: 3.5, leading: 17, bottom: 3.5, trailing: 17))
        }
    }

    private func historyRow(_ session: ConversationSession) -> some View {
        let isSelected = session.id == selectedSessionID
        return HStack(spacing: 0) {
            Button { onSelect(session.id) } label: {
                VStack(alignment: .leading, spacing: 12) {
                    Text(session.title)
                        .font(.system(size: rowSize, weight: isSelected ? .bold : .regular))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(historySubtitle(session))
                        .font(.system(size: captionSize))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
                .padding(.leading, 17)
                .padding(.trailing, 8)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isSelected ? "已选择" : "")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("menu.session.\(session.id)")

            Button {} label: {
                Text("▤")
                    .font(.title2)
                    .foregroundStyle(Palette.controlGlyph)
                    .frame(width: 38, height: 42)
                    .background(isSelected ? Palette.selectedControl : Palette.control,
                                in: RoundedRectangle(cornerRadius: 12))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(true)
            .accessibilityLabel("\(session.title)的对话统计")
            .accessibilityHint("当前对话统计将在后续版本中提供")
            .accessibilityIdentifier("menu.sessionStatistics.\(session.id)")
            .padding(.trailing, 7)
        }
        .background(isSelected ? Palette.selected : .clear, in: RoundedRectangle(cornerRadius: 13))
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 2).fill(Palette.selectedAccent)
                    .frame(width: 4, height: 60)
                    .accessibilityHidden(true)
            }
        }
    }

    private func historySubtitle(_ session: ConversationSession) -> String {
        // Use actual saved metadata; mockup dates/descriptions are not app data.
        guard let date = session.messages.last?.createdAt else { return session.prompt }
        return date.formatted(.dateTime.month().day().locale(Locale(identifier: "zh_CN"))) + " · " + session.prompt
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle().fill(Palette.divider).frame(height: 1)
                .accessibilityHidden(true)
            Text("轻松聊天，慢慢进步")
                .font(.system(size: captionSize))
                .foregroundStyle(Palette.secondary)
                .padding(.horizontal, 5)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }
}

private extension View {
    func menuListRow(insets: EdgeInsets) -> some View {
        listRowInsets(insets)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    func menuListStyle() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.vertical, 0, for: .scrollContent)
    }
}

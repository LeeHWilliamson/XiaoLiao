import SwiftUI

/// Approved warm Concept 02 drawer; root-owned routing and local history are unchanged.
struct ConversationNavigationMenu: View {
    @Environment(\.appStrings) private var strings
    let sessions: [ConversationSession]
    let selectedSessionID: String?
    let onSelect: (String) -> Void
    let onNewConversation: () -> Void
    let onSettings: () -> Void
    let onStatistics: () -> Void
    let onDismiss: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var isTitleFocused: Bool
    @ScaledMetric(relativeTo: .title) private var brandSize: CGFloat = 24
    @ScaledMetric(relativeTo: .headline) private var actionSize: CGFloat = 17
    @ScaledMetric(relativeTo: .body) private var rowSize: CGFloat = 17
    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 12
    private typealias Palette = XiaoLiaoTheme.NavigationMenu

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Button(action: onDismiss) {
                    XiaoLiaoTheme.historyScrim.opacity(0.28)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(strings("关闭菜单"))
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
                .overlay { UnevenRoundedRectangle(bottomTrailingRadius: 24, topTrailingRadius: 24).strokeBorder(XiaoLiaoTheme.border, lineWidth: 1) }
                .ignoresSafeArea(edges: .vertical)
        }
    }

    private var menuHeader: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(strings("小聊"))
                        .font(.system(size: brandSize, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($isTitleFocused)
                    Text(strings("你的英语学习伙伴"))
                        .font(.caption).foregroundStyle(Palette.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onSettings) {
                    Text(strings("设置")).font(.subheadline)
                        .padding(.horizontal, 12).frame(minWidth: 44, minHeight: 44)
                        .xiaoLiaoCard(cornerRadius: 16)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(strings("对话设置"))
                .accessibilityIdentifier("menu.settings")
            }
            .padding(.bottom, 16)
            Button(action: onNewConversation) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(strings("开始新对话"))
                        .font(.system(size: actionSize, weight: .semibold))
                    Text(strings("聊一个新的话题")).font(.caption)
                }
                .foregroundStyle(XiaoLiaoTheme.surface)
                .padding(20)
                .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
                .background(Palette.newConversation, in: RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("menu.new")
            Button(action: onStatistics) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(strings("学习进度"))
                        .font(.system(size: actionSize, weight: .semibold))
                    Text(strings("看看你的英语进步"))
                        .font(.caption).foregroundStyle(Palette.progressSubtitle)
                }
                .foregroundStyle(Palette.text)
                .padding(20)
                .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
                .xiaoLiaoCard()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(strings("学习进度，全部对话的学习统计"))
            .accessibilityIdentifier("menu.statistics")
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
    }

    private var historyHeading: some View {
        Text(strings("以前的对话"))
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 16)
    }

    private var historyRows: some View {
        ForEach(sessions) { session in
            historyRow(session)
                .menuListRow(insets: EdgeInsets(top: 4, leading: 24, bottom: 4, trailing: 24))
        }
    }

    private func historyRow(_ session: ConversationSession) -> some View {
        let isSelected = session.id == selectedSessionID
        return HStack(spacing: 0) {
            Button { onSelect(session.id) } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(session.title)
                        .font(.system(size: rowSize, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(historySubtitle(session))
                        .font(.system(size: captionSize))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
                .padding(.leading, 16)
                .padding(.trailing, 8)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isSelected ? strings("已选择") : "")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("menu.session.\(session.id)")

            Button {} label: {
                Text("▤")
                    .font(.body)
                    .foregroundStyle(Palette.controlGlyph.opacity(0.35))
                    .frame(width: 38, height: 42)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(true)
            .accessibilityLabel(strings("\(session.title)的对话统计"))
            .accessibilityHint(strings("当前对话统计将在后续版本中提供"))
            .accessibilityIdentifier("menu.sessionStatistics.\(session.id)")
            .padding(.trailing, 7)
        }
        .background(isSelected ? Palette.selected : .clear, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isSelected ? XiaoLiaoTheme.green : .clear, lineWidth: 1)
        }
    }

    private func historySubtitle(_ session: ConversationSession) -> String {
        // Use actual saved metadata; mockup dates/descriptions are not app data.
        guard let date = session.messages.last?.createdAt else { return session.prompt }
        return date.formatted(.dateTime.month().day().locale(strings.locale)) + " · " + session.prompt
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle().fill(Palette.divider).frame(height: 1)
                .accessibilityHidden(true)
            Text(strings("轻松聊天，慢慢进步"))
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

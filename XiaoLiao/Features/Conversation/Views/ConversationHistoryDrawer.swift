import SwiftUI

struct ConversationHistoryDrawer: View {
    let sessions: [ConversationSession]
    let selectedSessionID: String?
    let onSelect: (String) -> Void
    let onNewConversation: () -> Void
    let onDismiss: () -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 36
    @ScaledMetric(relativeTo: .title) private var rowSize: CGFloat = 32
    @AccessibilityFocusState private var isTitleFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Button(action: onDismiss) {
                    XiaoLiaoTheme.historyScrim.opacity(0.69)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭以前的对话")
                .accessibilityIdentifier("history.scrim")

                HStack(alignment: .top, spacing: 0) {
                    panel
                        .frame(width: min(330, geometry.size.width * 0.75))

                    VStack {
                        ArtworkButton(label: "关闭以前的对话", glyph: .backGlyph, ring: .backRing, action: onDismiss)
                            .accessibilityIdentifier("history.close")
                            .padding(.top, 12)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape, onDismiss)
        .accessibilityIdentifier("history.drawer")
        .onAppear { isTitleFocused = true }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            Text("以前的对话")
                .font(.system(size: titleSize))
                .foregroundStyle(XiaoLiaoTheme.historyForeground)
                .multilineTextAlignment(.center)
                .shadow(color: XiaoLiaoTheme.historyGlow.opacity(0.25), radius: 6)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 100)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($isTitleFocused)

            Divider().overlay(XiaoLiaoTheme.historyForeground)

            List {
                historyRow(title: "新对话", isSelected: false, identifier: "history.new", action: onNewConversation)
                ForEach(sessions) { session in
                    historyRow(
                        title: session.title,
                        isSelected: session.id == selectedSessionID,
                        identifier: "history.session.\(session.id)"
                    ) {
                        onSelect(session.id)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.vertical, 0, for: .scrollContent)
            .accessibilityIdentifier("history.list")
        }
        .background(XiaoLiaoTheme.historyBackground.ignoresSafeArea())
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(XiaoLiaoTheme.historyForeground)
                .frame(width: 3)
                .ignoresSafeArea(edges: .vertical)
                .accessibilityHidden(true)
        }
    }

    private func historyRow(title: String, isSelected: Bool, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: rowSize))
                .foregroundStyle(isSelected ? XiaoLiaoTheme.historySelectionInk : XiaoLiaoTheme.historyForeground)
                .multilineTextAlignment(.center)
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 76)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets())
        .listRowBackground(isSelected ? XiaoLiaoTheme.historyForeground : XiaoLiaoTheme.historyBackground)
        .listRowSeparatorTint(XiaoLiaoTheme.historyForeground)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .accessibilityValue(isSelected ? "已选择" : "")
        .accessibilityIdentifier(identifier)
    }
}

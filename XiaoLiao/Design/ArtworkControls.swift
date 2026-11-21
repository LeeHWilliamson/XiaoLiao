import SwiftUI

/// Reuses the bundled glyphs inside the approved rounded concept controls.
struct ArtworkIcon: View {
    let glyph: FigmaArtwork
    var ring: FigmaArtwork = .controlRing
    var size: CGFloat = 44
    var isActive = false

    var body: some View {
        let bound: CGFloat = glyph == .menuGlyph || glyph == .menuOpenGlyph ? 22 : 24
        let scale = min(bound / glyph.size.width, bound / glyph.size.height)
        let isSend = glyph == .sendAudioGlyph
        let isMenu = glyph == .menuGlyph || glyph == .menuOpenGlyph
        Image(glyph.rawValue)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: glyph.size.width * scale, height: glyph.size.height * scale)
            .foregroundStyle(isSend || isActive ? XiaoLiaoTheme.surface : isMenu ? XiaoLiaoTheme.red : XiaoLiaoTheme.ink)
            .frame(width: size, height: size)
            .background(isSend ? XiaoLiaoTheme.red : isActive ? XiaoLiaoTheme.green : XiaoLiaoTheme.surface,
                        in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSend || isActive ? Color.clear : XiaoLiaoTheme.border, lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

struct ArtworkButton: View {
    @Environment(\.appStrings) private var strings
    let label: String
    let glyph: FigmaArtwork
    var ring: FigmaArtwork = .controlRing
    var size: CGFloat = 44
    var isActive = false
    var isAvailable = true
    var unavailableHint = "将在后续版本中提供"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ArtworkIcon(glyph: glyph, ring: ring, size: size, isActive: isActive)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.45)
        .accessibilityLabel(strings(label))
        .accessibilityHint(isAvailable ? "" : strings(unavailableHint))
    }
}

struct ConversationHeader: View {
    let onMenu: () -> Void
    var onStatistics: (() -> Void)? = nil
    @Environment(\.appStrings) private var strings
    var title = "小聊"
    var subtitle: String? = nil
    var titleFont: Font = .headline

    init(title: String = "小聊", subtitle: String? = nil, titleFont: Font = .headline, onStatistics: (() -> Void)? = nil, onMenu: @escaping () -> Void) {
        self.onStatistics = onStatistics
        self.title = title
        self.subtitle = subtitle
        self.onMenu = onMenu
        self.titleFont = titleFont
    }

    var body: some View {
        HStack(spacing: 16) {
            NavigationMenuButton(action: onMenu)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(titleFont)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(XiaoLiaoTheme.muted)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if let onStatistics {
                ArtworkButton(label: strings("本次对话统计"), glyph: .statsGlyph, action: onStatistics)
                    .accessibilityIdentifier("conversation.statistics")
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
    }
}

struct NavigationMenuButton: View {
    @Environment(\.appStrings) private var strings
    var isExpanded = false
    let action: () -> Void

    var body: some View {
        ArtworkButton(label: isExpanded ? strings("关闭菜单") : strings("打开菜单"),
                      glyph: isExpanded ? .menuOpenGlyph : .menuGlyph, action: action)
            .accessibilityValue(isExpanded ? strings("已展开") : strings("已收起"))
            .accessibilityIdentifier(isExpanded ? "menu.close" : "navigation.menu")
    }
}

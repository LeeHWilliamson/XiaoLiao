import SwiftUI

/// Original Figma layers, composed at their original proportions.
struct ArtworkIcon: View {
    let glyph: FigmaArtwork
    var ring: FigmaArtwork = .controlRing
    var size: CGFloat = 64
    var isActive = false

    var body: some View {
        // The microphone glyph comes from the 53-point text composer.
        let scale = size / (glyph == .microphoneGlyph ? 53 : ring.size.width)
        ZStack {
            if isActive {
                Circle().fill(XiaoLiaoTheme.green).padding(1)
            }
            FigmaImage(artwork: ring)
            Image(glyph.rawValue)
                .renderingMode(isActive ? .template : .original)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white)
                .frame(width: glyph.size.width * scale, height: glyph.size.height * scale)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct ArtworkButton: View {
    let label: String
    let glyph: FigmaArtwork
    var ring: FigmaArtwork = .controlRing
    var size: CGFloat = 64
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
        .accessibilityLabel(label)
        .accessibilityHint(isAvailable ? "" : unavailableHint)
    }
}

/// This is custom artwork in Figma, rather than a standard titled navigation bar.
struct ConversationHeader: View {
    var onHistory: (() -> Void)?
    var onSettings: (() -> Void)?
    var onStatistics: (() -> Void)?

    var body: some View {
        HStack {
            ArtworkButton(
                label: "以前的对话",
                glyph: .historyGlyph,
                isAvailable: onHistory != nil,
                action: { onHistory?() }
            )
            .accessibilityIdentifier("conversation.history")
            Spacer()
            ArtworkButton(label: "全部学习统计", glyph: .statsGlyph, isAvailable: onStatistics != nil) {
                onStatistics?()
            }
            .accessibilityIdentifier("conversation.statistics")
            Spacer()
            ArtworkButton(label: "对话设置", glyph: .settingsGlyph, isAvailable: onSettings != nil) {
                onSettings?()
            }
            .accessibilityIdentifier("conversation.settings")
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
}

import SwiftUI

enum XiaoLiaoTheme {
    static let paper = Color("Paper")
    static let ink = Color("Ink")
    static let green = Color.accentColor
    static let surface = Color(red: 1, green: 252/255.0, blue: 245/255.0)
    static let border = Color(red: 216/255.0, green: 206/255.0, blue: 187/255.0)
    static let muted = Color(red: 129/255.0, green: 118/255.0, blue: 102/255.0)
    static let red = Color(red: 175/255.0, green: 80/255.0, blue: 68/255.0)
    static let prompt = Color("PromptSurface")
    static let promptBorder = Color("PromptBorder")
    static let watermark = Color("Watermark")
    static let historyBackground = Color("HistoryBackground")
    static let historyForeground = Color("HistoryForeground")
    static let historySelectionInk = Color("HistorySelectionInk")
    static let historyScrim = Color("HistoryScrim")
    static let historyGlow = Color("HistoryGlow")
    static let settingsSelection = Color("SettingsSelection")
    static let systemRequest = Color("SystemRequest")
    static let systemResponse = Color("SystemResponse")
    static let systemRequestText = Color("SystemRequestText")

    /// Approved Concept 02: warm surfaces shared with the conversation screens.
    enum NavigationMenu {
        static let background = XiaoLiaoTheme.surface
        static let text = XiaoLiaoTheme.ink
        static let secondary = XiaoLiaoTheme.muted
        static let control = XiaoLiaoTheme.surface
        static let newConversation = XiaoLiaoTheme.green
        static let progress = XiaoLiaoTheme.surface
        static let progressGlyph = XiaoLiaoTheme.green
        static let progressSubtitle = XiaoLiaoTheme.muted
        static let divider = XiaoLiaoTheme.border
        static let selected = XiaoLiaoTheme.surface
        static let selectedAccent = XiaoLiaoTheme.green
        static let selectedControl = Color.clear
        static let controlGlyph = XiaoLiaoTheme.muted
    }
}

struct PaperBackground: View {
    var showsWatermark = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                XiaoLiaoTheme.paper
                Image("PaperTexture")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .opacity(0.018)
                    .clipped()
                if showsWatermark {
                    Text("小聊")
                        .font(.system(size: min(geometry.size.width * 0.45, 200), weight: .bold))
                        .foregroundStyle(XiaoLiaoTheme.watermark.opacity(0.56))
                        .offset(y: -65)
                        .accessibilityHidden(true)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    func xiaoLiaoCard(cornerRadius: CGFloat = 20) -> some View {
        background(XiaoLiaoTheme.surface, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(XiaoLiaoTheme.border, lineWidth: 1)
            }
    }
}

import SwiftUI

enum XiaoLiaoTheme {
    static let paper = Color("Paper")
    static let ink = Color("Ink")
    static let green = Color.accentColor
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

    /// Unified navigation drawer, Figma 41:710. Keep its palette local to the
    /// menu so existing conversation/settings/statistics colors are preserved.
    enum NavigationMenu {
        static let background = Color(red: 24/255.0, green: 37/255.0, blue: 54/255.0)
        static let text = Color(red: 228/255.0, green: 232/255.0, blue: 234/255.0)
        static let secondary = Color(red: 170/255.0, green: 182/255.0, blue: 196/255.0)
        static let control = Color(red: 36/255.0, green: 51/255.0, blue: 72/255.0)
        static let newConversation = Color(red: 115/255.0, green: 147/255.0, blue: 105/255.0)
        static let progress = Color(red: 65/255.0, green: 91/255.0, blue: 82/255.0)
        static let progressGlyph = Color(red: 220/255.0, green: 232/255.0, blue: 215/255.0)
        static let progressSubtitle = Color(red: 228/255.0, green: 238/255.0, blue: 225/255.0)
        static let divider = Color(red: 59/255.0, green: 75/255.0, blue: 92/255.0)
        static let selected = Color(red: 48/255.0, green: 75/255.0, blue: 83/255.0)
        static let selectedAccent = Color(red: 165/255.0, green: 196/255.0, blue: 160/255.0)
        static let selectedControl = Color(red: 66/255.0, green: 98/255.0, blue: 87/255.0)
        static let controlGlyph = Color(red: 186/255.0, green: 199/255.0, blue: 207/255.0)
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
                    .opacity(0.03)
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

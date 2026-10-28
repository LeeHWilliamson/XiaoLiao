import SwiftUI

enum XiaoLiaoTheme {
    static let paper = Color("Paper")
    static let ink = Color("Ink")
    static let green = Color.accentColor
    static let prompt = Color("PromptSurface")
    static let promptBorder = Color("PromptBorder")
    static let watermark = Color("Watermark")
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

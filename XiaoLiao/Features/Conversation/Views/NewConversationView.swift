import SwiftUI

struct NewConversationView: View {
    @Bindable var viewModel: ConversationViewModel
    let onStart: () -> Void
    @FocusState private var isPromptFocused: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 48
    @ScaledMetric(relativeTo: .largeTitle) private var subtitleSize: CGFloat = 36
    @ScaledMetric(relativeTo: .title3) private var promptSize: CGFloat = 20

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    ConversationHeader()

                    Text("小聊")
                        .font(.system(size: titleSize, weight: .bold))
                        .padding(.top, 12)

                    Text("聊聊天，练英语")
                        .font(.system(size: subtitleSize, weight: .bold))
                        .multilineTextAlignment(.center)
                        .padding(.top, 30)
                        .padding(.horizontal)

                    promptEditor
                        .frame(maxWidth: 323)
                        .frame(height: max(240, min(344, geometry.size.height * 0.39)))
                        .padding(.horizontal, 32)
                        .padding(.top, 33)

                    Button {
                        isPromptFocused = false
                        onStart()
                    } label: {
                        Text("聊天")
                            .font(.system(size: titleSize, weight: .bold))
                            .foregroundStyle(.white.opacity(viewModel.canStart ? 1 : 0.33))
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 102)
                            .background(XiaoLiaoTheme.green.opacity(viewModel.canStart ? 1 : 0.37))
                            .clipShape(RoundedRectangle(cornerRadius: 45))
                            .overlay {
                                RoundedRectangle(cornerRadius: 45)
                                    .strokeBorder(XiaoLiaoTheme.ink.opacity(viewModel.canStart ? 1 : 0.38), lineWidth: 2)
                            }
                            .shadow(color: .black.opacity(0.1), radius: 2, y: 4)
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.canStart)
                    .accessibilityIdentifier("conversation.start")
                    .frame(maxWidth: 291)
                    .padding(.horizontal, 40)
                    .padding(.top, 36)

                    Spacer(minLength: 32)
                }
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height, alignment: .top)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background { PaperBackground(showsWatermark: true) }
        .foregroundStyle(XiaoLiaoTheme.ink)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var promptEditor: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                if viewModel.prompt.isEmpty {
                    Text("你可以选择提供聊天话题和对话发生的实际场景。")
                        .foregroundStyle(.black.opacity(0.73))
                        .padding(.horizontal, 5)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                TextEditor(text: $viewModel.prompt)
                    .scrollContentBackground(.hidden)
                    .focused($isPromptFocused)
                    .accessibilityLabel("聊天话题和场景")
                    .accessibilityIdentifier("conversation.prompt")
            }
            .font(.system(size: promptSize, weight: .bold))

            HStack {
                Spacer()
                ArtworkButton(label: "帮我想个提示吧", glyph: .suggestGlyph, ring: .suggestRing, size: 56) {
                    viewModel.suggestPrompt()
                }
                .accessibilityIdentifier("conversation.suggest")
            }
        }
        .padding(10)
        .background(XiaoLiaoTheme.prompt.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(XiaoLiaoTheme.promptBorder, lineWidth: 2)
        }
    }
}

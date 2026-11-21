import SwiftUI

struct NewConversationView: View {
    @Environment(\.appStrings) private var strings
    @Bindable var viewModel: ConversationViewModel
    let onStart: () -> Void
    let onMenu: () -> Void
    @FocusState private var isPromptFocused: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 44

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ConversationHeader {
                        isPromptFocused = false
                        onMenu()
                    }
                    VStack(alignment: .leading, spacing: 32) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(strings("聊聊天，\n练英语。"))
                                .font(.system(size: titleSize, weight: .semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(strings("听一听，说一说，在对话中练习英语。"))
                                .font(.subheadline)
                                .foregroundStyle(XiaoLiaoTheme.muted)
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            Text(strings("聊天话题")).font(.headline)
                            promptEditor
                                .frame(minHeight: 228)
                            Button {
                                isPromptFocused = false
                                onStart()
                            } label: {
                                Text(strings("开始聊天"))
                                    .font(.headline)
                                    .foregroundStyle(XiaoLiaoTheme.surface)
                                    .frame(maxWidth: .infinity, minHeight: 60)
                                    .background(XiaoLiaoTheme.green, in: RoundedRectangle(cornerRadius: 20))
                            }
                            .buttonStyle(.plain)
                            .disabled(!viewModel.canStart)
                            .opacity(viewModel.canStart ? 1 : 0.45)
                            .accessibilityIdentifier("conversation.start")
                            .padding(.top, 8)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, geometry.size.height < 650 ? 20 : 48)
                    Spacer(minLength: 40)
                    Text(strings("轻松聊天，慢慢进步"))
                        .font(.caption)
                        .foregroundStyle(XiaoLiaoTheme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 28)
                }
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height, alignment: .top)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background { PaperBackground() }
        .foregroundStyle(XiaoLiaoTheme.ink)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var promptEditor: some View {
        VStack(spacing: 16) {
            ZStack(alignment: .topLeading) {
                if viewModel.prompt.isEmpty {
                    Text(strings("请提供聊天话题和对话发生的实际场景，或点击按钮生成提示。"))
                        .foregroundStyle(XiaoLiaoTheme.muted)
                        .padding(.horizontal, 5)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                TextEditor(text: $viewModel.prompt)
                    .scrollContentBackground(.hidden)
                    .focused($isPromptFocused)
                    .frame(minHeight: 120)
                    .accessibilityLabel(strings("聊天话题和场景"))
                    .accessibilityIdentifier("conversation.prompt")
            }
            .font(.body)
            HStack {
                Spacer(minLength: 0)
                Button {
                    viewModel.suggestPrompt()
                } label: {
                    HStack(spacing: 8) {
                        Image(FigmaArtwork.suggestGlyph.rawValue)
                            .renderingMode(.template).resizable().scaledToFit()
                            .frame(width: 20, height: 20)
                            .accessibilityHidden(true)
                        Text(strings("帮我想个话题")).font(.subheadline)
                    }
                    .foregroundStyle(XiaoLiaoTheme.green)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(XiaoLiaoTheme.paper, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(strings("帮我想个提示吧"))
                .accessibilityIdentifier("conversation.suggest")
            }
        }
        .padding(20)
        .xiaoLiaoCard(cornerRadius: 24)
    }
}

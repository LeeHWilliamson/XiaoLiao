import SwiftUI

struct ConversationFeedView: View {
    @Bindable var viewModel: ConversationViewModel
    let onHistory: () -> Void
    let onSettings: () -> Void
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ConversationHeader(
                onHistory: {
                    isComposerFocused = false
                    onHistory()
                },
                onSettings: {
                    isComposerFocused = false
                    onSettings()
                }
            )

            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 40) {
                            ForEach(viewModel.messages) { message in
                                MessageRow(viewModel: viewModel, message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 28)
                        .frame(maxWidth: 560)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: geometry.size.height, alignment: .top)
                        .background {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    viewModel.deselectMessage()
                                    isComposerFocused = false
                                }
                                .accessibilityIdentifier("conversation.feedBackground")
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: viewModel.messages.count) { _, _ in
                        if let id = viewModel.messages.last?.id {
                            proxy.scrollTo(id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composer
        }
        .background { PaperBackground() }
        .foregroundStyle(XiaoLiaoTheme.ink)
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: viewModel.editingMessageID) { _, id in
            if id != nil { isComposerFocused = true }
        }
        .accessibilityIdentifier("conversation.feed")
    }

    private var composer: some View {
        VStack(spacing: 12) {
            Rectangle().fill(XiaoLiaoTheme.ink).frame(height: 1)
            if viewModel.inputMode == .voice {
                voiceComposer
            } else {
                textComposer
            }
        }
        .padding(.bottom, 8)
        .background { PaperBackground() }
    }

    private var voiceComposer: some View {
        VStack(spacing: 0) {
            Button(action: recordingUnavailable) {
                FigmaImage(artwork: .recordSurface)
                    .frame(width: 247, height: 81)
                    .overlay(alignment: .top) {
                        Image(systemName: "waveform.badge.microphone")
                            .font(.system(size: 52))
                            .foregroundStyle(.white)
                            .padding(.top, 8)
                    }
            }
            .buttonStyle(.plain)
            .disabled(true)
            .accessibilityLabel("录音")
            .accessibilityHint("本版本使用本地示例消息，尚未接入录音")

            HStack {
                ArtworkButton(label: "切换说话者", glyph: .voiceModeGlyph, isAvailable: false, action: recordingUnavailable)
                Spacer()
                ArtworkButton(label: "键盘输入", glyph: .keyboardGlyph) {
                    viewModel.inputMode = .text
                    isComposerFocused = true
                }
                .accessibilityIdentifier("conversation.keyboard")
            }
            .padding(.horizontal, 20)
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    private var textComposer: some View {
        HStack(spacing: 14) {
            ArtworkButton(label: "切换说话者", glyph: .voiceModeGlyph, size: 53, isAvailable: false, action: recordingUnavailable)

            TextField("Textbox", text: $viewModel.draft, axis: .vertical)
                .font(.title2)
                .lineLimit(1...4)
                .padding(10)
                .frame(minHeight: 53)
                .background(.white)
                .overlay { Rectangle().strokeBorder(.black, lineWidth: 1) }
                .focused($isComposerFocused)
                .submitLabel(.send)
                .onSubmit {
                    if viewModel.submitDraft() { isComposerFocused = false }
                }
                .accessibilityLabel(viewModel.editingMessageID == nil ? "输入消息" : "编辑消息")
                .accessibilityIdentifier("conversation.draft")

            ArtworkButton(label: "返回语音输入", glyph: .microphoneGlyph, size: 53) {
                isComposerFocused = false
                viewModel.showVoiceInput()
            }
            .accessibilityIdentifier("conversation.microphone")
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    private func recordingUnavailable() {
        // Disabled: real audio recording/playback is outside milestone one.
    }
}

import SwiftUI
import UIKit

struct ConversationFeedView: View {
    @Bindable var viewModel: ConversationViewModel
    let onHistory: () -> Void
    let onSettings: () -> Void
    @FocusState private var isComposerFocused: Bool
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            if id != nil && viewModel.inputMode == .text { isComposerFocused = true }
        }
        .onDisappear { viewModel.leaveFeed() }
        .alert("音频", isPresented: Binding(
            get: { viewModel.audio.issue != nil },
            set: { if !$0 { viewModel.audio.issue = nil } }
        )) {
            if viewModel.audio.issue?.offersSettings == true {
                Button("打开设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
            Button("好", role: .cancel) { viewModel.audio.issue = nil }
        } message: {
            Text(viewModel.audio.issue?.message ?? "")
        }
        .accessibilityIdentifier("conversation.feed")
    }

    private var composer: some View {
        VStack(spacing: 12) {
            if viewModel.audio.hasDraft { recordingRow }
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
            Button { viewModel.beginRecording() } label: {
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
            .disabled(viewModel.audio.hasDraft)
            .opacity(viewModel.audio.hasDraft ? 0.5 : 1)
            .accessibilityLabel("录音")
            .accessibilityHint("轻点开始录音；录音时可暂停试听或发送")
            .accessibilityIdentifier("conversation.record")

            HStack {
                ArtworkButton(label: "切换说话者", glyph: .voiceModeGlyph, isAvailable: false, action: recordingUnavailable)
                Spacer()
                ArtworkButton(label: "键盘输入", glyph: .keyboardGlyph) {
                    viewModel.showTextInput()
                    isComposerFocused = true
                }
                .accessibilityHint(viewModel.audio.hasDraft ? "切换到键盘会丢弃未发送的录音" : "")
                .accessibilityIdentifier("conversation.keyboard")
            }
            .padding(.horizontal, 20)
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    private var recordingRow: some View {
        let audio = viewModel.audio
        return HStack(spacing: 8) {
            ArtworkButton(
                label: audio.recordingState == .review ? "继续录音" : "暂停录音并试听",
                glyph: .pauseGlyph,
                size: 64,
                isActive: audio.recordingState == .review,
                isAvailable: audio.recordingState == .recording || audio.recordingState == .review,
                unavailableHint: "正在请求麦克风权限或整理录音，请稍候"
            ) {
                if audio.recordingState == .recording {
                    Task { await audio.pauseRecording() }
                } else {
                    audio.startRecording()
                }
            }
            .accessibilityIdentifier("conversation.pauseRecording")

            Button { audio.previewDraft() } label: {
                HStack(spacing: 0) {
                    Text(audio.recordingState == .processing || audio.recordingState == .requestingPermission
                         ? "…" : "\(max(0, Int(audio.duration)))秒")
                        .font(.callout.monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(minWidth: 40)
                    FigmaImage(artwork: .recordingWaveLead)
                        .frame(width: 41.9879, height: 31)
                    FigmaImage(artwork: .recordingWaveTrail)
                        .frame(width: 42, height: 29)
                }
                .opacity(reduceMotion || audio.recordingState != .recording ? 1 : 0.4 + 0.6 * audio.level)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 77)
                .background(XiaoLiaoTheme.green)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(.black, lineWidth: 2) }
            }
            .buttonStyle(.plain)
            .disabled(audio.recordingState != .review)
            .accessibilityLabel(audio.playbackID == "recording-draft" && audio.isPlaying ? "暂停试听" : "试听录音")
            .accessibilityValue("\(Int(audio.duration))秒")
            .accessibilityHint("暂停录音后可轻点试听；切换键盘或离开对话会丢弃录音")
            .accessibilityIdentifier("conversation.previewRecording")

            ArtworkButton(
                label: "发送录音", glyph: .sendAudioGlyph, size: 64,
                isAvailable: audio.canSend,
                unavailableHint: "正在请求麦克风权限或整理录音，请稍候"
            ) {
                Task { await viewModel.sendRecording() }
            }
            .accessibilityIdentifier("conversation.sendRecording")
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
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
        // Speaker switching is outside milestone three.
    }
}

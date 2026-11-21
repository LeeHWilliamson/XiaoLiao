import SwiftUI
import UIKit

struct ConversationFeedView: View {
    @Environment(\.appStrings) private var strings
    @Bindable var viewModel: ConversationViewModel
    let onMenu: () -> Void
    let onStatistics: () -> Void
    @FocusState private var isComposerFocused: Bool
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ConversationHeader(title: viewModel.history.first { $0.id == viewModel.activeSessionID }?.title ?? strings("小聊"), onStatistics: {
                isComposerFocused = false
                onStatistics()
            }) {
                isComposerFocused = false
                onMenu()
            }

            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 24) {
                            ForEach(viewModel.messages, id: \.logicalMessageID) { message in
                                MessageRow(viewModel: viewModel, message: message)
                                    .id(message.logicalMessageID)
                            }
                            if viewModel.hasPendingResponse {
                                replyStatus.id("conversation.replyStatus")
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
                        if viewModel.hasPendingResponse {
                            proxy.scrollTo("conversation.replyStatus", anchor: .bottom)
                        } else if let id = viewModel.messages.last?.logicalMessageID {
                            proxy.scrollTo(id, anchor: .bottom)
                        }
                    }
                    .onChange(of: viewModel.isGeneratingReply) { _, _ in
                        if viewModel.hasPendingResponse { proxy.scrollTo("conversation.replyStatus", anchor: .bottom) }
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
        .alert(strings("音频"), isPresented: Binding(
            get: { viewModel.audio.issue != nil },
            set: { if !$0 { viewModel.audio.issue = nil } }
        )) {
            if viewModel.audio.issue?.offersSettings == true {
                Button(strings("打开设置")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
            Button(strings("好"), role: .cancel) { viewModel.audio.issue = nil }
        } message: {
            Text(strings.error(viewModel.audio.issue?.message ?? ""))
        }
        .accessibilityIdentifier("conversation.feed")
    }

    private var composer: some View {
        VStack(spacing: 16) {
            Rectangle().fill(XiaoLiaoTheme.border).frame(height: 1)
            if viewModel.audio.hasDraft {
                recordingRow
                HStack(spacing: 12) {
                    Button {
                        viewModel.showTextInput()
                        isComposerFocused = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(FigmaArtwork.keyboardGlyph.rawValue)
                                .renderingMode(.template).resizable().scaledToFit()
                                .frame(width: 20, height: 16)
                            Text(strings("键盘")).font(.subheadline)
                        }
                        .padding(.horizontal, 12).frame(minHeight: 44)
                        .xiaoLiaoCard(cornerRadius: 16)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(strings("键盘输入"))
                    .accessibilityIdentifier("conversation.keyboard")
                    Text(strings("切换到键盘会丢弃未发送的录音"))
                        .font(.caption).foregroundStyle(XiaoLiaoTheme.muted)
                }
            } else if viewModel.inputMode == .voice {
                voiceComposer
            } else {
                textComposer
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 16)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background { PaperBackground() }
    }

    private var replyStatus: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                if viewModel.isGeneratingReply {
                    Text("…")
                        .font(.largeTitle)
                        .foregroundStyle(XiaoLiaoTheme.green)
                        .padding(20)
                        .frame(width: 240)
                        .frame(minHeight: 72, alignment: .leading)
                        .xiaoLiaoCard()
                        .accessibilityLabel(viewModel.pendingTranscription != nil ? strings("正在转写英语录音") : viewModel.pendingReply?.request.kind == .system ? strings("小聊系统正在回复") : strings("对话伙伴正在回复"))
                        .accessibilityIdentifier("conversation.replyLoading")
                    if viewModel.pendingTranscription != nil {
                        Text(strings("正在转写英语…首次使用可能需要下载识别模型。"))
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("conversation.transcribing")
                    }
                } else {
                    Text(strings.error(viewModel.pendingResponseFailure ?? (viewModel.pendingTranscription != nil ? strings("转写尚未完成，录音已保留，可以重试。") : strings("上次回复尚未完成，可以重试。"))))
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(strings("重试")) { viewModel.retryReply() }
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityIdentifier("conversation.retryReply")
                        Spacer()
                        Button(strings("暂不重试")) { viewModel.dismissFailedReply() }
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityIdentifier("conversation.dismissReply")
                    }
                    .font(.callout.bold())
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                }
            }
            .frame(maxWidth: 300, alignment: .leading)
            Spacer(minLength: 40)
        }
        .padding(.leading, 28)
        .padding(.trailing, 24)
        .accessibilityElement(children: .contain)
    }

    private var voiceComposer: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(spacing: 8) {
                systemModeButton(size: 44)
                Text(strings("系统")).font(.caption).foregroundStyle(XiaoLiaoTheme.muted)
            }
            .frame(width: 56)
            Button { viewModel.beginRecording() } label: {
                HStack(spacing: 12) {
                    Image(systemName: "waveform.badge.microphone")
                        .font(.system(size: 30))
                        .accessibilityHidden(true)
                    Text(strings("开始录音")).font(.headline)
                }
                .foregroundStyle(XiaoLiaoTheme.surface)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(XiaoLiaoTheme.red, in: RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canSubmitMessage)
            .opacity(viewModel.canSubmitMessage ? 1 : 0.45)
            .accessibilityLabel(strings("录音"))
            .accessibilityHint(strings("轻点开始录音；录音时可暂停试听或发送"))
            .accessibilityIdentifier("conversation.record")
            VStack(spacing: 8) {
                ArtworkButton(label: strings("键盘输入"), glyph: .keyboardGlyph) {
                    viewModel.showTextInput()
                    isComposerFocused = true
                }
                .accessibilityIdentifier("conversation.keyboard")
                Text(strings("键盘")).font(.caption).foregroundStyle(XiaoLiaoTheme.muted)
            }
            .frame(width: 56)
        }
    }

    private var recordingRow: some View {
        let audio = viewModel.audio
        return VStack(alignment: .leading, spacing: 12) {
            Text(recordingStatus(audio))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(audio.recordingState == .recording ? XiaoLiaoTheme.red : XiaoLiaoTheme.green)
            HStack(alignment: .center, spacing: 12) {
                VStack(spacing: 8) {
                    ArtworkButton(label: strings("重新录音"), glyph: .repeatGlyph,
                                  isAvailable: audio.canSend) { viewModel.restartRecording() }
                        .accessibilityHint(strings("丢弃当前未发送的录音，从头开始录制"))
                        .accessibilityIdentifier("conversation.restartRecording")
                    Text(strings("重录")).font(.caption).foregroundStyle(XiaoLiaoTheme.muted)
                }
                Button { Task { await audio.toggleDraftControl() } } label: {
                    HStack(spacing: 12) {
                        if audio.canSend {
                            Image((audio.recordingState == .recording || audio.isPreviewingDraft
                                   ? FigmaArtwork.pauseGlyph : .playGlyph).rawValue)
                                .renderingMode(.template).resizable().scaledToFit()
                                .frame(width: 22, height: 26)
                                .frame(minWidth: 44, minHeight: 44)
                        } else {
                            ProgressView().tint(.white).frame(width: 44, height: 44)
                        }
                        HStack(spacing: 0) {
                            recordingWave(.recordingWaveLead)
                            recordingWave(.recordingWaveTrail)
                        }
                        .frame(maxWidth: 84)
                        .frame(height: 31)
                        .scaleEffect(x: 1, y: reduceMotion || audio.recordingState != .recording ? 1 : 0.65 + 0.35 * audio.level)
                    }
                    .foregroundStyle(XiaoLiaoTheme.surface)
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 72)
                    .background(XiaoLiaoTheme.green, in: RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(.plain)
                .disabled(!audio.canSend)
                .accessibilityLabel(strings(audio.draftControlLabel))
                .accessibilityValue(strings("\(Int(audio.duration))秒"))
                .accessibilityHint(strings("录音时轻点结束采集，随后轻点播放或暂停试听；左侧按钮丢弃当前录音并重新录制"))
                .accessibilityIdentifier("conversation.recordingControl")
                VStack(spacing: 8) {
                    ArtworkButton(label: strings("发送录音"), glyph: .sendAudioGlyph,
                                  isAvailable: audio.canSend,
                                  unavailableHint: strings("正在请求麦克风权限或整理录音，请稍候")) {
                        Task { await viewModel.sendRecording() }
                    }
                    .accessibilityIdentifier("conversation.sendRecording")
                    Text(strings("发送")).font(.caption).foregroundStyle(XiaoLiaoTheme.muted)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func recordingWave(_ artwork: FigmaArtwork) -> some View {
        Image(artwork.rawValue)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    private func recordingStatus(_ audio: ConversationAudioController) -> String {
        switch audio.recordingState {
        case .idle: strings("录音")
        case .requestingPermission: strings("等待权限…")
        case .processing: strings("正在整理…")
        case .recording: strings("录音中 · \(max(0, Int(audio.duration)))秒")
        case .review: strings("\(audio.isPreviewingDraft ? strings("试听中") : strings("待发送")) · \(max(1, Int(audio.duration.rounded(.up))))秒")
        }
    }

    private var textComposer: some View {
        HStack(spacing: 12) {
            systemModeButton(size: 44)

            HStack(alignment: .bottom, spacing: 0) {
                TextField(viewModel.isSystemMessageMode ? strings("向系统提问或调整对话…") : strings("输入英文消息…"), text: $viewModel.draft, axis: .vertical)
                    .font(.body)
                    .lineLimit(1...4)
                    .padding(10)
                    .frame(minHeight: 64)
                    .focused($isComposerFocused)
                    .disabled(!viewModel.canSubmitMessage)
                    .submitLabel(.send)
                    .onSubmit(sendText)
                    .accessibilityLabel(viewModel.isSystemMessageMode ? strings("向小聊发送系统消息") : viewModel.editingMessageID == nil ? strings("输入消息") : strings("编辑消息"))
                    .accessibilityHint(viewModel.canSubmitMessage ? "" : strings("请等待回复，或处理失败的请求后继续"))
                    .accessibilityIdentifier("conversation.draft")

                ArtworkButton(label: viewModel.isSystemMessageMode ? strings("发送系统消息") : viewModel.editingMessageID == nil ? strings("发送消息") : strings("发送修改"),
                              glyph: .sendAudioGlyph, size: 44,
                              isAvailable: viewModel.canSubmitMessage && !viewModel.audio.hasDraft
                                && !viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                              unavailableHint: strings("请输入消息，并等待当前回复完成后发送"), action: sendText)
                    .accessibilityIdentifier("conversation.sendText")
                    .padding(.trailing, 4)
                    .padding(.bottom, 4)
            }
            .background(viewModel.isSystemMessageMode ? XiaoLiaoTheme.systemRequest : XiaoLiaoTheme.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(viewModel.isSystemMessageMode ? XiaoLiaoTheme.systemResponse : XiaoLiaoTheme.border, lineWidth: 1) }

            ArtworkButton(label: strings("返回语音输入"), glyph: .microphoneGlyph, size: 44,
                          isAvailable: !viewModel.isSystemMessageMode,
                          unavailableHint: strings("系统消息仅支持文字，请先取消系统消息模式")) {
                isComposerFocused = false
                viewModel.showVoiceInput()
            }
            .opacity(viewModel.isSystemMessageMode ? 0.4 : 1)
            .accessibilityIdentifier("conversation.microphone")
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    private func sendText() {
        if viewModel.submitDraft() { isComposerFocused = false }
    }

    private func systemModeButton(size: CGFloat) -> some View {
        ArtworkButton(
            label: viewModel.isSystemMessageMode ? strings("取消系统消息") : strings("联系小聊"),
            glyph: .voiceModeGlyph, size: size,
            isAvailable: !viewModel.audio.hasDraft && viewModel.canSubmitMessage,
            unavailableHint: strings("请先处理当前录音或等待中的回复")
        ) {
            viewModel.toggleSystemMessageMode()
            isComposerFocused = viewModel.inputMode == .text
        }
        .accessibilityValue(viewModel.isSystemMessageMode ? strings("已选择") : strings("未选择"))
        .accessibilityHint(viewModel.audio.hasDraft ? strings("请先发送或取消当前录音") : strings("将下一条文字消息发给小聊系统；再次轻点取消。"))
        .accessibilityIdentifier("conversation.systemMode")
    }
}

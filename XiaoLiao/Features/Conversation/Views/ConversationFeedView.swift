import SwiftUI
import UIKit

struct ConversationFeedView: View {
    @Bindable var viewModel: ConversationViewModel
    let onMenu: () -> Void
    @FocusState private var isComposerFocused: Bool
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ConversationHeader {
                isComposerFocused = false
                onMenu()
            }

            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 40) {
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

    private var replyStatus: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                if viewModel.isGeneratingReply {
                    FigmaImage(artwork: .audioOval)
                        .frame(width: 209, height: 86)
                        .overlay { Text("…").font(.largeTitle.bold()).foregroundStyle(XiaoLiaoTheme.ink) }
                        .overlay(alignment: .bottomLeading) {
                            FigmaImage(artwork: .audioTail)
                                .frame(width: 17.2822, height: 23.3026)
                                .rotationEffect(.degrees(-154.56))
                                .offset(x: 10, y: -2)
                        }
                        .accessibilityLabel(viewModel.pendingTranscription != nil ? "正在转写英语录音" : viewModel.pendingReply?.request.kind == .system ? "小聊系统正在回复" : "对话伙伴正在回复")
                        .accessibilityIdentifier("conversation.replyLoading")
                    if viewModel.pendingTranscription != nil {
                        Text("正在转写英语…首次使用可能需要下载识别模型。")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("conversation.transcribing")
                    }
                } else {
                    Text(viewModel.pendingResponseFailure ?? (viewModel.pendingTranscription != nil ? "转写尚未完成，录音已保留，可以重试。" : "上次回复尚未完成，可以重试。"))
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("重试") { viewModel.retryReply() }
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityIdentifier("conversation.retryReply")
                        Spacer()
                        Button("暂不重试") { viewModel.dismissFailedReply() }
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityIdentifier("conversation.dismissReply")
                    }
                    .font(.callout.bold())
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                }
            }
            .frame(maxWidth: 225, alignment: .leading)
            Spacer(minLength: 40)
        }
        .padding(.leading, 38)
        .padding(.trailing, 24)
        .accessibilityElement(children: .contain)
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
            .disabled(viewModel.audio.hasDraft || !viewModel.canSubmitMessage)
            .opacity(viewModel.audio.hasDraft || !viewModel.canSubmitMessage ? 0.5 : 1)
            .accessibilityLabel("录音")
            .accessibilityHint("轻点开始录音；录音时可暂停试听或发送")
            .accessibilityIdentifier("conversation.record")

            HStack {
                systemModeButton(size: 64)
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
            Button { viewModel.restartRecording() } label: {
                FigmaImage(artwork: .controlRing)
                    .frame(width: 64, height: 64)
                    .overlay {
                        FigmaImage(artwork: .repeatGlyph)
                            .frame(width: 32, height: 32 * FigmaArtwork.repeatGlyph.size.height / FigmaArtwork.repeatGlyph.size.width)
                    }
            }
            .buttonStyle(.plain)
            .disabled(!audio.canSend)
            .accessibilityLabel("重新录音")
            .accessibilityHint("丢弃当前未发送的录音，从头开始录制")
            .accessibilityIdentifier("conversation.restartRecording")

            Button { Task { await audio.toggleDraftControl() } } label: {
                HStack(spacing: 10) {
                    if audio.canSend {
                        Image((audio.recordingState == .recording || audio.isPreviewingDraft
                               ? FigmaArtwork.pauseGlyph : .playGlyph).rawValue)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                    } else {
                        ProgressView().tint(.white)
                            .frame(width: 24, height: 24)
                    }
                    VStack(spacing: 6) {
                        Text(recordingStatus(audio))
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 0) {
                            recordingWave(.recordingWaveLead)
                            recordingWave(.recordingWaveTrail)
                        }
                        .frame(maxWidth: 84)
                        .frame(height: 31)
                        .scaleEffect(x: 1, y: reduceMotion || audio.recordingState != .recording ? 1 : 0.65 + 0.35 * audio.level)
                    }
                    .frame(maxWidth: .infinity)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 77)
                .background(XiaoLiaoTheme.green)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(.black, lineWidth: 2) }
            }
            .buttonStyle(.plain)
            .disabled(!audio.canSend)
            .accessibilityLabel(audio.draftControlLabel)
            .accessibilityValue("\(Int(audio.duration))秒")
            .accessibilityHint("录音时轻点结束采集，随后轻点播放或暂停试听；左侧按钮丢弃当前录音并重新录制")
            .accessibilityIdentifier("conversation.recordingControl")

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
        case .idle: "录音"
        case .requestingPermission: "等待权限…"
        case .processing: "正在整理…"
        case .recording: "录音中 · \(max(0, Int(audio.duration)))秒"
        case .review: "\(audio.isPreviewingDraft ? "试听中" : "待发送") · \(max(1, Int(audio.duration.rounded(.up))))秒"
        }
    }

    private var textComposer: some View {
        HStack(spacing: 14) {
            systemModeButton(size: 53)

            HStack(alignment: .bottom, spacing: 0) {
                TextField(viewModel.isSystemMessageMode ? "联系推荐人" : "Textbox", text: $viewModel.draft, axis: .vertical)
                    .font(.title2)
                    .lineLimit(1...4)
                    .padding(10)
                    .frame(minHeight: 53)
                    .focused($isComposerFocused)
                    .disabled(!viewModel.canSubmitMessage)
                    .submitLabel(.send)
                    .onSubmit(sendText)
                    .accessibilityLabel(viewModel.isSystemMessageMode ? "向小聊发送系统消息" : viewModel.editingMessageID == nil ? "输入消息" : "编辑消息")
                    .accessibilityHint(viewModel.canSubmitMessage ? "" : "请等待回复，或处理失败的请求后继续")
                    .accessibilityIdentifier("conversation.draft")

                ArtworkButton(label: viewModel.isSystemMessageMode ? "发送系统消息" : viewModel.editingMessageID == nil ? "发送消息" : "发送修改",
                              glyph: .sendAudioGlyph, size: 44,
                              isAvailable: viewModel.canSubmitMessage && !viewModel.audio.hasDraft
                                && !viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                              unavailableHint: "请输入消息，并等待当前回复完成后发送", action: sendText)
                    .accessibilityIdentifier("conversation.sendText")
                    .padding(.trailing, 4)
                    .padding(.bottom, 4)
            }
            .background(viewModel.isSystemMessageMode ? XiaoLiaoTheme.systemRequest : .white)
            .overlay { Rectangle().strokeBorder(.black, lineWidth: 1) }

            ArtworkButton(label: "返回语音输入", glyph: .microphoneGlyph, size: 53,
                          isAvailable: !viewModel.isSystemMessageMode,
                          unavailableHint: "系统消息仅支持文字，请先取消系统消息模式") {
                isComposerFocused = false
                viewModel.showVoiceInput()
            }
            .opacity(viewModel.isSystemMessageMode ? 0.4 : 1)
            .accessibilityIdentifier("conversation.microphone")
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    private func sendText() {
        if viewModel.submitDraft() { isComposerFocused = false }
    }

    private func systemModeButton(size: CGFloat) -> some View {
        ArtworkButton(
            label: viewModel.isSystemMessageMode ? "取消系统消息" : "联系小聊",
            glyph: .voiceModeGlyph, size: size,
            isAvailable: !viewModel.audio.hasDraft && viewModel.canSubmitMessage,
            unavailableHint: "请先处理当前录音或等待中的回复"
        ) {
            viewModel.toggleSystemMessageMode()
            isComposerFocused = viewModel.inputMode == .text
        }
        .accessibilityValue(viewModel.isSystemMessageMode ? "已选择" : "未选择")
        .accessibilityHint(viewModel.audio.hasDraft ? "请先发送或取消当前录音" : "将下一条文字消息发给小聊系统；再次轻点取消。")
        .accessibilityIdentifier("conversation.systemMode")
    }
}

import SwiftUI

struct MessageRow: View {
    @Environment(\.appStrings) private var strings
    let viewModel: ConversationViewModel
    let message: Message

    private var isSelected: Bool { viewModel.selectedMessageID == message.id }
    private var isPartner: Bool { message.senderRole == .aiPartner }
    private var isSpokenLearner: Bool { message.senderRole == .user && message.modality == .spoken }
    private var sourceText: String? {
        if let transcript = message.transcription?.text { return transcript }
        if case let .text(text) = message.content { return text }
        return nil
    }
    private var showsAudio: Bool {
        if case .audio = message.content { return true }
        return isSpokenLearner || (isPartner && message.status == .complete && sourceText?.isEmpty == false)
    }
    private var foreground: Color { isSpokenLearner ? XiaoLiaoTheme.surface : XiaoLiaoTheme.ink }
    private var duration: String {
        if let seconds = message.audioAttachment?.durationSeconds { return strings("\(Int(seconds.rounded(.up)))秒") }
        return strings("语音")
    }

    var body: some View {
        if message.purpose == .systemAssistance, case let .text(text) = message.content {
            systemRow(text)
        } else {
            HStack(alignment: .top, spacing: 12) {
                if !isPartner {
                    Spacer(minLength: isSelected ? 0 : 48)
                    if isSelected { actionRail }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(isPartner ? strings("对方") : strings("我"))
                        .font(.caption).foregroundStyle(XiaoLiaoTheme.muted)
                    if showsAudio { audioBubble } else { textBubble }
                    detailCard
                }
                .frame(maxWidth: 300, alignment: .leading)
                if isPartner {
                    if isSelected { actionRail }
                    Spacer(minLength: isSelected ? 0 : 48)
                }
            }
            .padding(.horizontal, 28)
        }
    }

    private func systemRow(_ text: String) -> some View {
        let isResponse = message.senderRole == .system
        return HStack {
            if !isResponse { Spacer(minLength: 48) }
            VStack(alignment: .leading, spacing: 8) {
                Text(isResponse ? strings("系统") : strings("对系统说"))
                    .font(.caption)
                Text(text).font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(isResponse ? XiaoLiaoTheme.surface : XiaoLiaoTheme.systemRequestText)
            .padding(16)
            .frame(maxWidth: 300, alignment: .leading)
            .background(isResponse ? XiaoLiaoTheme.systemResponse : XiaoLiaoTheme.systemRequest,
                        in: RoundedRectangle(cornerRadius: 20))
            .accessibilityLabel("\(isResponse ? strings("小聊系统回复") : strings("我发给小聊系统的消息"))：\(text)")
            .accessibilityIdentifier("message.\(message.logicalMessageID)")
            if isResponse { Spacer(minLength: 48) }
        }
        .padding(.horizontal, 28)
    }

    private var audioBubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    if !isSelected { viewModel.selectMessage(message.id) }
                    viewModel.perform(.play, on: message.id)
                } label: {
                    Image((isPlaying ? FigmaArtwork.pauseGlyph : .playGlyph).rawValue)
                        .renderingMode(.template).resizable().scaledToFit()
                        .frame(width: 18, height: 22)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.isAvailable(.play, for: message))
                .opacity(viewModel.isAvailable(.play, for: message) ? 1 : 0.45)
                .accessibilityLabel(isPlaying ? strings("暂停播放") : strings("播放"))
                .accessibilityIdentifier("audio.play.\(message.id)")

                Button { viewModel.selectMessage(message.id) } label: {
                    HStack(spacing: 12) {
                        if let sourceText, !sourceText.isEmpty {
                            MessageRhythmDots(text: sourceText)
                        } else {
                            Image(FigmaArtwork.recordingWaveLead.rawValue)
                                .renderingMode(.template).resizable().scaledToFit()
                                .frame(maxWidth: 84, maxHeight: 30)
                        }
                        Text(duration).font(.subheadline).foregroundStyle(foreground).fixedSize()
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPartner ? strings("对话伙伴的语音，\(duration)") : strings("语音消息 · \(duration)"))
                .accessibilityValue(isSelected ? strings("已选择") : strings("未选择"))
                .accessibilityHint(strings("轻点显示或隐藏消息操作"))
                .accessibilityIdentifier("message.\(message.logicalMessageID)")
            }
            if (!isPartner || viewModel.details[message.id] == .transcript), let sourceText {
                Text(sourceText).font(.body).foregroundStyle(foreground)
                    .onTapGesture { viewModel.selectMessage(message.id) }
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("\(isPartner ? "detail" : "caption").\(message.id)")
            }
            if viewModel.audio.playbackID == message.id, viewModel.audioClip(for: message) != nil {
                ProgressView(value: viewModel.audio.playbackProgress)
                    .tint(foreground)
                    .accessibilityLabel(strings("播放"))
                    .accessibilityValue(strings("播放进度\(Int(viewModel.audio.playbackProgress * 100))%"))
                    .accessibilityIdentifier("playback.\(message.id)")
            }
        }
        .foregroundStyle(isSpokenLearner ? XiaoLiaoTheme.surface : XiaoLiaoTheme.green)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSpokenLearner ? XiaoLiaoTheme.green : XiaoLiaoTheme.surface,
                    in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(isSelected ? XiaoLiaoTheme.green : isSpokenLearner ? .clear : XiaoLiaoTheme.border, lineWidth: 1)
        }
    }

    private var textBubble: some View {
        Button { viewModel.selectMessage(message.id) } label: {
            Text(sourceText ?? "")
                .font(.body).multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(foreground)
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .xiaoLiaoCard()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(isPartner ? strings("对话伙伴的消息") : strings("我的消息"))：\(sourceText ?? "")")
        .accessibilityValue(isSelected ? strings("已选择") : strings("未选择"))
        .accessibilityHint(strings("轻点显示或隐藏消息操作"))
        .accessibilityIdentifier("message.\(message.logicalMessageID)")
    }

    private var isPlaying: Bool { viewModel.audio.playbackID == message.id && viewModel.audio.isPlaying }

    private var actionRail: some View {
        VStack(spacing: 8) {
            ForEach(viewModel.actions(for: message)) { action in
                Button { viewModel.perform(action, on: message.id) } label: {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) {
                            actionGlyph(action).frame(width: 16, height: 18)
                            Text(actionTitle(action)).font(.caption)
                        }
                        actionGlyph(action).frame(width: 20, height: 22)
                    }
                    .foregroundStyle(XiaoLiaoTheme.green)
                    .frame(width: 64)
                    .frame(minHeight: 44)
                    .xiaoLiaoCard(cornerRadius: 16)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(isActive(action) ? XiaoLiaoTheme.green : .clear, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.isAvailable(action, for: message))
                .opacity(viewModel.isAvailable(action, for: message) ? 1 : 0.45)
                .accessibilityLabel(isPlaying && action == .play ? strings("暂停播放") : strings(action.label))
                .accessibilityValue(isActive(action) ? strings("已选择") : strings("未选择"))
                .accessibilityHint(viewModel.isAvailable(action, for: message) ? "" : strings("此消息没有可播放的录音或可朗读的伙伴回复，或该操作暂不可用"))
                .accessibilityIdentifier("action.\(message.id).\(action.rawValue)")
            }
        }
        .frame(width: 64)
        .accessibilityElement(children: .contain)
    }

    private func actionGlyph(_ action: MessageAction) -> some View {
        let glyph: FigmaArtwork = switch action {
        case .transcribe: .transcribeGlyph
        case .translate: .translateGlyph
        case .edit: .editGlyph
        case .play: isPlaying ? .pauseGlyph : .repeatGlyph
        case .repeatAudio: .repeatGlyph
        }
        return Image(glyph.rawValue).renderingMode(.template).resizable().scaledToFit()
    }

    private func actionTitle(_ action: MessageAction) -> String {
        switch action {
        case .transcribe: strings("英文")
        case .translate: strings("中文")
        case .play: isPlaying ? strings("暂停播放") : strings("重播")
        case .edit, .repeatAudio: strings(action.label)
        }
    }

    private func isActive(_ action: MessageAction) -> Bool {
        (action == .transcribe && viewModel.details[message.id] == .transcript)
            || (action == .translate && viewModel.details[message.id] == .translation)
            || (action == .edit && viewModel.editingMessageID == message.id)
            || (action == .play && isPlaying)
    }

    @ViewBuilder
    private var detailCard: some View {
        if viewModel.details[message.id] == .translation, let text = viewModel.detailText(for: message) {
            VStack(alignment: .leading, spacing: 12) {
                Text(strings("中文翻译")).font(.caption).foregroundStyle(XiaoLiaoTheme.green)
                Text(text).font(.body).foregroundStyle(XiaoLiaoTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .xiaoLiaoCard()
            .accessibilityIdentifier("detail.\(message.id)")
        }
    }
}

/// Static word-position marks only. No elapsed-time guess is presented as
/// speech alignment or pronunciation scoring; real word timing is a later step.
private struct MessageRhythmDots: View {
    let text: String
    private var wordCount: Int { text.split(whereSeparator: { $0.isWhitespace }).count }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 12) {
                ForEach(0..<wordCount, id: \.self) { _ in
                    Image(FigmaArtwork.transcriptDot.rawValue)
                        .renderingMode(.template).resizable().scaledToFit()
                        .frame(width: 16, height: 16 * 15 / 17)
                }
            }
            .background { Rectangle().frame(height: 1).opacity(0.35) }
        }
        .scrollIndicators(.hidden)
        .frame(height: 32)
        .accessibilityHidden(true)
    }
}

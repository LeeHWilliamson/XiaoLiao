import SwiftUI

struct MessageRow: View {
    let viewModel: ConversationViewModel
    let message: ConversationMessage
    @ScaledMetric(relativeTo: .title3) private var messageSize: CGFloat = 20
    @ScaledMetric(relativeTo: .title2) private var systemMessageSize: CGFloat = 24

    private var isSelected: Bool { viewModel.selectedMessageID == message.id }

    var body: some View {
        if message.purpose == .system, case let .text(text) = message.content {
            systemRow(text: text)
        } else {
            switch message.content {
            case let .audio(duration, _):
                audioRow(duration: duration)
            case let .text(text):
                textRow(text: text)
            }
        }
    }

    private func systemRow(text: String) -> some View {
        let isResponse = message.sender == .system
        return HStack(alignment: .top, spacing: 0) {
            if !isResponse { Spacer(minLength: 64) }
            Text(text)
                .font(.system(size: systemMessageSize))
                .multilineTextAlignment(.leading)
                .foregroundStyle(isResponse ? .white : XiaoLiaoTheme.systemRequestText)
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 147, alignment: .topLeading)
                .background(isResponse ? XiaoLiaoTheme.systemResponse : XiaoLiaoTheme.systemRequest)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(isResponse ? .white : .black, lineWidth: isResponse ? 4 : 2)
                }
                .overlay(alignment: .bottomTrailing) {
                    if !isResponse {
                        FigmaImage(artwork: .textTail)
                            .frame(width: 17.2822, height: 23.3026)
                            .rotationEffect(.degrees(150))
                            .offset(x: 4, y: 8)
                    }
                }
                .frame(maxWidth: 225)
                .accessibilityLabel("\(isResponse ? "小聊系统示例回复" : "我发给小聊系统的消息")：\(text)")
                .accessibilityIdentifier("message.\(message.id)")
            if isResponse { Spacer(minLength: 64) }
        }
        .padding(.leading, isResponse ? 53 : 24)
        .padding(.trailing, isResponse ? 24 : 69)
    }

    private func audioRow(duration: Int) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Button {
                    viewModel.selectMessage(message.id)
                } label: {
                    FigmaImage(artwork: .audioOval)
                        .frame(width: 209, height: 86)
                        .overlay {
                            HStack(spacing: 22) {
                                FigmaImage(artwork: .speakingGlyph)
                                    .frame(width: 51.19, height: 51.2245)
                                Text("\(duration) sec")
                                    .font(.callout.bold())
                                    .foregroundStyle(Color(white: 146.0 / 255))
                            }
                        }
                        .overlay(alignment: .bottomLeading) {
                            FigmaImage(artwork: .audioTail)
                                .frame(width: 17.2822, height: 23.3026)
                                .rotationEffect(.degrees(-154.56))
                                .offset(x: 10, y: -2)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("对话伙伴的语音，\(duration)秒")
                .accessibilityValue(isSelected ? "已选择" : "未选择")
                .accessibilityHint("轻点显示或隐藏消息操作")
                .accessibilityIdentifier("message.\(message.id)")
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        actionRail(isAudio: true)
                            .offset(x: 30, y: -10)
                    }
                }
                .padding(.leading, 22)

                detailCard
            }
            Spacer(minLength: 64)
        }
        .padding(.leading, 16)
    }

    private func textRow(text: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Spacer(minLength: 64)
            VStack(alignment: .center, spacing: 26) {
                Button {
                    viewModel.selectMessage(message.id)
                } label: {
                    Text(text)
                        .font(.system(size: messageSize))
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(message.communicationMethod == .voice ? .white : .black)
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 147, alignment: .topLeading)
                        .background(message.communicationMethod == .voice ? XiaoLiaoTheme.green : .white)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(viewModel.editingMessageID == message.id && viewModel.audio.hasDraft ? Color.gray : .black, lineWidth: 2)
                        }
                        .overlay(alignment: .bottomTrailing) {
                            FigmaImage(artwork: .textTail)
                                .frame(width: 17.2822, height: 23.3026)
                                .rotationEffect(.degrees(150))
                                .offset(x: 4, y: 8)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("我的消息：\(text)")
                .accessibilityValue(isSelected ? "已选择" : "未选择")
                .accessibilityHint("轻点显示或隐藏消息操作")
                .accessibilityIdentifier("message.\(message.id)")
                .overlay(alignment: .topLeading) {
                    if isSelected {
                        actionRail(isAudio: false)
                            .offset(x: -49)
                    }
                }

                detailCard
            }
            .frame(maxWidth: 225)
        }
        .padding(.leading, 24)
        .padding(.trailing, 65)
    }

    private func actionRail(isAudio: Bool) -> some View {
        VStack(spacing: isAudio ? -2 : 7) {
            ForEach(Array(viewModel.actions(for: message).enumerated()), id: \.element.id) { index, action in
                ArtworkButton(
                    label: action == .play && viewModel.audio.playbackID == message.id && viewModel.audio.isPlaying
                        ? "暂停播放" : action.label,
                    glyph: action.glyph(isAudio: isAudio),
                    ring: action.ring(isAudio: isAudio),
                    size: action == .translate && !isAudio ? 43.8146 : 40.6344,
                    isActive: (action == .translate && viewModel.details[message.id] == .translation)
                        || (action == .transcribe && viewModel.details[message.id] == .transcript)
                        || (action == .edit && viewModel.editingMessageID == message.id)
                        || (action == .play && viewModel.audio.playbackID == message.id && viewModel.audio.isPlaying),
                    isAvailable: viewModel.isAvailable(action, for: message),
                    unavailableHint: action == .translate ? "此消息没有本地示例翻译" : "此示例没有录音文件，或该操作暂不可用"
                ) {
                    viewModel.perform(action, on: message.id)
                }
                .accessibilityIdentifier("action.\(message.id).\(action.rawValue)")
                .offset(x: isAudio ? [0.0, 20.0, 8.0][index] : 0)
            }
        }
        .frame(width: 44)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var detailCard: some View {
        if viewModel.details[message.id] == .playback, let clip = message.localAudio {
            playbackCard(clip)
        } else if let text = viewModel.detailText(for: message) {
            let isTranscript = viewModel.details[message.id] == .transcript
            VStack(alignment: .leading, spacing: 10) {
                Text(text)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isTranscript {
                    FigmaImage(artwork: .transcriptLine)
                        .frame(height: 2)
                        .overlay {
                            HStack(spacing: 0) {
                                ForEach(0..<5) { index in
                                    FigmaImage(artwork: .transcriptDot)
                                        .frame(width: 17, height: 15)
                                    if index < 4 { Spacer(minLength: 0) }
                                }
                            }
                        }
                        .padding(.vertical, 7)
                }
            }
            .foregroundStyle(isTranscript ? .white : XiaoLiaoTheme.ink)
            .padding(10)
            .frame(maxWidth: 201, minHeight: isTranscript ? 89 : 52, alignment: .topLeading)
            .background(isTranscript ? XiaoLiaoTheme.green : .white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10).strokeBorder(.black, lineWidth: 2)
            }
            .accessibilityIdentifier("detail.\(message.id)")
        }
    }

    private func playbackCard(_ clip: LocalAudioClip) -> some View {
        let progress = viewModel.audio.playbackID == message.id ? viewModel.audio.playbackProgress : 0
        return VStack(alignment: .leading, spacing: 10) {
            Text("语音消息 · \(clip.durationLabel)")
                .font(.callout)
            FigmaImage(artwork: .transcriptLine)
                .frame(maxWidth: 182)
                .frame(height: 2)
                .overlay {
                    HStack(spacing: 0) {
                        ForEach(0..<7) { index in
                            FigmaImage(artwork: .transcriptDot)
                                .frame(width: 17, height: 15)
                                .opacity(Double(index) / 6 <= progress ? 1 : 0.45)
                            if index < 6 { Spacer(minLength: 0) }
                        }
                    }
                }
                .padding(.vertical, 7)
        }
        .foregroundStyle(.white)
        .padding(10)
        .frame(maxWidth: 201, minHeight: 89, alignment: .topLeading)
        .background(XiaoLiaoTheme.green)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.black, lineWidth: 2) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("语音消息，\(clip.durationLabel)")
        .accessibilityValue("播放进度\(Int(progress * 100))%")
        .accessibilityIdentifier("playback.\(message.id)")
    }
}

private extension MessageAction {
    func glyph(isAudio: Bool) -> FigmaArtwork {
        switch self {
        case .transcribe: .transcribeGlyph
        case .translate: isAudio ? .audioTranslateGlyph : .translateGlyph
        case .repeatAudio: .repeatGlyph
        case .play: .playGlyph
        case .edit: .editGlyph
        }
    }

    func ring(isAudio: Bool) -> FigmaArtwork {
        switch self {
        case .transcribe, .repeatAudio: .audioActionRing
        case .translate: isAudio ? .audioActionRing : .translateRing
        case .play: .actionRing
        case .edit: .editRing
        }
    }
}

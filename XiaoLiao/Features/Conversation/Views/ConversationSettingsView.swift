import SwiftUI

struct ConversationSettingsView: View {
    @Environment(\.appStrings) private var strings
    @AppStorage(AppLanguage.preferenceKey) private var gradingMode = false
    @Bindable var viewModel: ConversationViewModel
    let onMenu: () -> Void
    @State private var preferencesDraft = ""
    @State private var savedPreferences: String?
    @State private var preferencesIssue: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ConversationHeader(title: strings("对话设置"), titleFont: .title2.weight(.semibold), onMenu: onMenu)
                VStack(alignment: .leading, spacing: 28) {
                    Text(strings("对话选项调整后立即生效；学习偏好需保存。"))
                        .font(.subheadline).foregroundStyle(XiaoLiaoTheme.muted)
                    ConversationSettingSection(title: strings("语气"), identifier: "tone",
                        options: ConversationSettings.Tone.allCases, selection: Binding(get: { viewModel.settings.tone }, set: { value in
                            viewModel.updateSettings(.tone) { $0.tone = value }
                        }),
                        label: { strings($0.title) })
                    ConversationSettingSection(title: strings("用词难度"), identifier: "vocabulary",
                        options: ConversationSettings.Vocabulary.allCases, selection: Binding(get: { viewModel.settings.vocabulary }, set: { value in
                            viewModel.updateSettings(.vocabulary) { $0.vocabulary = value }
                        }),
                        label: { strings($0.title) })
                    ConversationSettingSection(title: strings("回复长度"), identifier: "replyLength",
                        options: ConversationSettings.ReplyLength.allCases, selection: Binding(get: { viewModel.settings.replyLength }, set: { value in
                            viewModel.updateSettings(.replyLength) { $0.replyLength = value }
                        }),
                        label: { strings.isEnglish && $0 == .complex ? "Long" : strings($0.title) })
                    learningPreferencesSection
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Grading Mode / 评分模式", isOn: $gradingMode)
                            .font(.headline).tint(XiaoLiaoTheme.green)
                            .accessibilityIdentifier("settings.gradingMode")
                        Text(strings("将界面按钮和说明显示为英语。错误信息始终使用英语。"))
                            .font(.caption).foregroundStyle(XiaoLiaoTheme.muted)
                    }
                    .padding(16)
                    .xiaoLiaoCard()
                    GradingAccessSettingsSection()
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 32)
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background { PaperBackground() }
        .foregroundStyle(XiaoLiaoTheme.ink)
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("settings.screen")
        .onAppear { preferencesDraft = viewModel.learningPreferences.text }
    }

    private var learningPreferencesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(strings("学习偏好")).font(.headline).accessibilityAddTraits(.isHeader)
            Text(strings("告诉我们你喜欢的话题、学习目标和希望的交流方式。"))
                .font(.subheadline).foregroundStyle(XiaoLiaoTheme.muted)
            TextField(strings("例如：我喜欢旅行，想练习工作交流。请多问一些后续问题。"),
                      text: $preferencesDraft, axis: .vertical)
                .lineLimit(4...8)
                .padding(12)
                .xiaoLiaoCard(cornerRadius: 16)
                .accessibilityLabel(strings("学习偏好"))
                .accessibilityIdentifier("settings.learningPreferences.input")
            Text(strings("\(preferencesDraft.utf16.count) / 2000 字符"))
                .font(.caption).foregroundStyle(XiaoLiaoTheme.muted)
            Text(strings("仅在此设备保存，并随 AI 对话请求发送。保存后适用于所有对话的后续新回复；已排队的请求和重试保留原内容。"))
                .font(.caption).foregroundStyle(XiaoLiaoTheme.muted)
            Text(strings("蓝色消息中的持续调整优先于对话主题，对话主题优先于这里的偏好。语气、用词和长度的明确设置仍适用于对应选项；未手动选择的选项仅作默认值。清空并保存即可移除偏好。"))
                .font(.caption).foregroundStyle(XiaoLiaoTheme.muted)
            if preferencesDraft.utf16.count > LearningPreferencesStore.maximumLength {
                Text("Learning preferences must be 2,000 characters or fewer.")
                    .font(.caption).foregroundStyle(XiaoLiaoTheme.red)
            }
            if let preferencesIssue {
                Text(strings.error(preferencesIssue)).font(.caption).foregroundStyle(XiaoLiaoTheme.red)
            }
            if savedPreferences == preferencesDraft {
                Text(strings("学习偏好已保存"))
                    .font(.caption).accessibilityIdentifier("settings.learningPreferences.saved")
            }
            Button(strings("保存学习偏好")) {
                do {
                    try viewModel.learningPreferences.save(preferencesDraft)
                    preferencesDraft = viewModel.learningPreferences.text
                    savedPreferences = preferencesDraft
                    preferencesIssue = nil
                } catch { preferencesIssue = error.localizedDescription }
            }
            .buttonStyle(.borderedProminent).tint(XiaoLiaoTheme.green)
            .frame(minHeight: 44)
            .disabled(preferencesDraft.utf16.count > LearningPreferencesStore.maximumLength ||
                      preferencesDraft == viewModel.learningPreferences.text)
            .accessibilityIdentifier("settings.learningPreferences.save")
        }
        .padding(16)
        .xiaoLiaoCard()
    }
}

/// Separate rounded choices from Concept 02, with a vertical accessibility layout.
private struct ConversationSettingSection<Option: Identifiable & Equatable>: View where Option.ID == String {
    @Environment(\.appStrings) private var strings
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let identifier: String
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 12) { choices }
            } else {
                HStack(spacing: 12) { choices }
            }
        }
    }

    @ViewBuilder
    private var choices: some View {
        ForEach(options) { option in
            Button { selection = option } label: {
                Text(label(option))
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(selection == option ? XiaoLiaoTheme.surface : XiaoLiaoTheme.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(selection == option ? XiaoLiaoTheme.green : XiaoLiaoTheme.surface,
                                in: RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(selection == option ? XiaoLiaoTheme.green : XiaoLiaoTheme.border, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title)，\(label(option))")
            .accessibilityValue(selection == option ? strings("已选择") : strings("未选择"))
            .accessibilityAddTraits(selection == option ? .isSelected : [])
            .accessibilityIdentifier("settings.\(identifier).\(option.id)")
        }
    }
}

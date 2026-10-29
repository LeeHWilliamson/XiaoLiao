import SwiftUI

struct ConversationSettingsView: View {
    @Environment(\.appStrings) private var strings
    @AppStorage(AppLanguage.preferenceKey) private var gradingMode = false
    @Bindable var viewModel: ConversationViewModel
    let onMenu: () -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 36

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Group {
                    if strings.isEnglish {
                        HStack(spacing: 16) {
                            NavigationMenuButton(action: onMenu)
                            Text(strings("对话设置"))
                                .font(.system(size: titleSize))
                                .lineLimit(2)
                                .minimumScaleFactor(0.75)
                                .accessibilityAddTraits(.isHeader)
                            Spacer(minLength: 0)
                        }
                    } else {
                        ZStack {
                            Text(strings("对话设置"))
                                .font(.system(size: titleSize))
                                .accessibilityAddTraits(.isHeader)
                            HStack {
                                NavigationMenuButton(action: onMenu)
                                Spacer()
                            }
                        }
                    }
                }
                .frame(minHeight: 80)
                .padding(.horizontal, 26)
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Grading Mode / 评分模式", isOn: $gradingMode)
                        .font(.headline)
                        .tint(XiaoLiaoTheme.green)
                        .accessibilityIdentifier("settings.gradingMode")
                    Text(strings("将界面按钮、说明和错误信息显示为英语。"))
                        .font(.caption)
                }
                .padding(16)
                .background(XiaoLiaoTheme.paper.opacity(0.9), in: RoundedRectangle(cornerRadius: 16))
                .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(XiaoLiaoTheme.ink.opacity(0.7), lineWidth: 1.5) }
                .padding(.horizontal, 26)
                .padding(.top, 20)

                VStack(spacing: 0) {
                    ConversationSettingSection(
                        title: strings("语气"), identifier: "tone",
                        options: ConversationSettings.Tone.allCases,
                        selection: $viewModel.settings.tone,
                        label: { strings($0.title) }
                    )
                    .padding(.bottom, 48)

                    ConversationSettingSection(
                        title: strings("用词难度"), identifier: "vocabulary",
                        options: ConversationSettings.Vocabulary.allCases,
                        selection: $viewModel.settings.vocabulary,
                        label: { strings($0.title) }
                    )
                    .padding(.bottom, 40)

                    ConversationSettingSection(
                        title: strings("回复长度"), identifier: "replyLength",
                        options: ConversationSettings.ReplyLength.allCases,
                        selection: $viewModel.settings.replyLength,
                        label: { strings.isEnglish && $0 == .complex ? "Long" : strings($0.title) }
                    )
                }
                .frame(maxWidth: 314)
                .padding(.horizontal, 28)
                .padding(.top, 32)
                .padding(.bottom, 40)
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background { PaperBackground(showsWatermark: true) }
        .foregroundStyle(XiaoLiaoTheme.ink)
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("settings.screen")
    }
}

/// Figma uses tall, tan and green brand capsules rather than the system segmented style.
private struct ConversationSettingSection<Option: Identifiable & Equatable>: View where Option.ID == String {
    @Environment(\.appStrings) private var strings
    let title: String
    let identifier: String
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String
    @ScaledMetric(relativeTo: .title) private var headingSize: CGFloat = 32
    @ScaledMetric(relativeTo: .title2) private var optionSize: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: headingSize))
                .frame(minHeight: 45, alignment: .bottomLeading)
                .padding(.leading, 12)
                .accessibilityAddTraits(.isHeader)

            FigmaImage(artwork: .settingsRule)
                .frame(height: 1)

            HStack(spacing: 0) {
                ForEach(options) { option in
                    Button {
                        selection = option
                    } label: {
                        Text(label(option))
                            .font(.system(size: optionSize))
                            .foregroundStyle(selection == option ? .white : XiaoLiaoTheme.ink)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 16)
                            .frame(maxWidth: .infinity, minHeight: 75)
                            .background {
                                if selection == option {
                                    Capsule().fill(XiaoLiaoTheme.settingsSelection)
                                }
                            }
                            .padding(.horizontal, 4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title)，\(label(option))")
                    .accessibilityValue(selection == option ? strings("已选择") : strings("未选择"))
                    .accessibilityAddTraits(selection == option ? .isSelected : [])
                    .accessibilityIdentifier("settings.\(identifier).\(option.id)")
                }
            }
            .padding(1)
            .background(XiaoLiaoTheme.prompt.opacity(0.75), in: Capsule())
            .padding(.top, 24)
            .accessibilityElement(children: .contain)
        }
    }
}

import SwiftUI

struct GradingAccessSettingsSection: View {
    @Environment(\.appStrings) private var strings
    @Environment(\.scenePhase) private var scenePhase
    @State private var access = GradingAccessController()
    @FocusState private var isCodeFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(strings("评分访问")).font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(strings("输入管理员提供的评分访问码，即可使用 AI 对话和语法分析。请勿输入 OpenAI 密钥。"))
                .font(.caption)
            Text(strings(access.hasSavedCode ? "此设备已保存评分访问码。" : "此设备尚未保存评分访问码。"))
                .font(.subheadline)
                .accessibilityIdentifier("grading.accessStatus")

            SecureField(strings("评分访问码"), text: $access.code)
                .textContentType(.oneTimeCode)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(XiaoLiaoTheme.paper, in: RoundedRectangle(cornerRadius: 16))
                .frame(minHeight: 44)
                .privacySensitive()
                .focused($isCodeFocused)
                .disabled(access.isChecking)
                .submitLabel(.go)
                .onSubmit { submit() }
                .accessibilityIdentifier("grading.accessCode")

            Button(action: submit) {
                HStack {
                    if access.isChecking { ProgressView().tint(.white) }
                    Text(strings(access.isChecking ? "正在验证…" : "验证并保存"))
                }
                .foregroundStyle(XiaoLiaoTheme.surface)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(XiaoLiaoTheme.green, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .disabled(access.isChecking || access.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(access.isChecking || access.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1)
            .accessibilityIdentifier("grading.saveCode")

            if access.hasSavedCode {
                Button(strings("移除访问码")) {
                    isCodeFocused = false
                    access.remove()
                }
                .frame(minHeight: 44)
                .accessibilityIdentifier("grading.removeCode")
            }
            if let issue = access.issue {
                Text(strings.error(issue)).font(.callout)
                    .accessibilityIdentifier("grading.accessError")
            }
            if let feedback = access.feedback {
                Text(strings(feedback)).font(.callout)
                    .accessibilityIdentifier("grading.accessFeedback")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .foregroundStyle(XiaoLiaoTheme.ink)
        .xiaoLiaoCard()
        .task { access.refresh() }
        .onDisappear { access.cancel() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { access.cancel() }
            if phase == .active { access.refresh() }
        }
    }

    private func submit() {
        isCodeFocused = false
        access.submit()
    }
}

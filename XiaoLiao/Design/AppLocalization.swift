import Foundation
import SwiftUI

/// App-wide presentation only; never part of a conversation or AI request.
nonisolated enum AppLanguage {
    static let preferenceKey: String = {
        #if DEBUG
        if let id = ProcessInfo.processInfo.environment["XIAOLIAO_UI_TEST_STORE"], UUID(uuidString: id) != nil {
            return "XiaoLiao.GradingMode.ui-test.\(id)"
        }
        #endif
        return "XiaoLiao.GradingMode"
    }()
}

/// Explicit bilingual UI copy. Translate at presentation time so persisted
/// failures switch languages too, without rewriting messages or history.
nonisolated struct AppStrings: Sendable {
    let isEnglish: Bool

    init(isEnglish: Bool = false) { self.isEnglish = isEnglish }

    var locale: Locale { Locale(identifier: isEnglish ? "en_US" : "zh_Hans_CN") }

    func callAsFunction(_ source: String) -> String {
        guard isEnglish else { return source }
        if let exact = Self.english[source] { return exact }
        let fullRange = NSRange(source.startIndex..., in: source)
        for template in Self.templates {
            guard let match = template.pattern.firstMatch(in: source, range: fullRange) else { continue }
            var values: [Int: String] = [:]
            for (index, slot) in template.slots.enumerated() {
                guard let range = Range(match.range(at: index + 1), in: source) else { continue }
                values[slot] = String(source[range])
            }
            // Build from the English template instead of repeated replacements:
            // inserted user titles can themselves contain braces or numbers.
            var result = ""
            var cursor = template.english.startIndex
            for token in Self.placeholder.matches(in: template.english, range: NSRange(template.english.startIndex..., in: template.english)) {
                guard let range = Range(token.range, in: template.english),
                      let number = Range(token.range(at: 1), in: template.english),
                      let slot = Int(template.english[number]) else { continue }
                result += template.english[cursor..<range.lowerBound]
                result += values[slot] ?? String(template.english[range])
                cursor = range.upperBound
            }
            result += template.english[cursor...]
            return result
        }
        return source
    }

    func error(_ source: String) -> String {
        let translated = self(source)
        if isEnglish, translated.range(of: "\\p{Han}", options: .regularExpression) != nil {
            // Unknown future server errors still have understandable English UI.
            return "Something went wrong. Please try again."
        }
        return translated
    }

    private struct Template: Sendable {
        let pattern: NSRegularExpression
        let slots: [Int]
        let english: String
        let specificity: Int
    }

    private static let placeholder = try! NSRegularExpression(pattern: "\\{([0-9]+)\\}")
    private static let templates: [Template] = english.compactMap { key, value in
        let markers = placeholder.matches(in: key, range: NSRange(key.startIndex..., in: key))
        guard !markers.isEmpty else { return nil }
        var pattern = "\\A", slots: [Int] = [], cursor = key.startIndex, literalCount = 0
        for marker in markers {
            guard let range = Range(marker.range, in: key), let slotRange = Range(marker.range(at: 1), in: key),
                  let slot = Int(key[slotRange]) else { return nil }
            let literal = String(key[cursor..<range.lowerBound])
            literalCount += literal.count
            pattern += NSRegularExpression.escapedPattern(for: literal) + "(.*?)"
            slots.append(slot)
            cursor = range.upperBound
        }
        let suffix = String(key[cursor...])
        pattern += NSRegularExpression.escapedPattern(for: suffix) + "\\z"
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else { return nil }
        return Template(pattern: expression, slots: slots, english: value, specificity: literalCount + suffix.count)
    }.sorted { $0.specificity > $1.specificity }

    private static let english: [String: String] = [
        "AI 服务尚未配置，请联系测试管理员。": "AI service is not configured. Please contact the test administrator.",
        "AI 服务暂不可用，请稍后重试。": "AI service is unavailable. Please try again later.",
        "AI 服务暂未返回结果，请稍后重试。": "AI service timed out. Please try again later.",
        "AI 服务繁忙，请稍后重试。": "AI service is busy. Please try again later.",
        "AI 语法分析 · 根据本条消息的上下文判断": "AI grammar analysis · Evaluated in this message's context",
        "AI 返回的数据不完整，请重试。": "AI returned incomplete data. Please retry.",
        "MATTR · 每日记录": "MATTR · Daily history",
        "{0} · {1}秒": "{0} · {1}s",
        "{0} · 趋势": "{0} · Trend",
        "{0} 个新词": "{0} new words",
        "{0}每日准确率": "Daily {0} accuracy",
        "{0}的对话统计": "Statistics for {0}",
        "{0}秒": "{0}s",
        "{0}，每日准确率": "{0}, daily accuracy",
        "— 表示尚无分析结果。每次发送和编辑都计为一次练习。": "— means no analysis is available. Each submission and edit counts as a practice attempt.",
        "上次回复尚未完成，可以重试。": "The previous reply did not finish. You can retry.",
        "上次语法分析未完成，请重试。": "The previous grammar analysis did not finish. Please retry.",
        "丢弃当前未发送的录音，从头开始录制": "Discard the unsent take and record again from the beginning",
        "中等": "Medium",
        "主谓一致": "Subject–verb agreement",
        "主题或消息过长，最多支持 4000 字符。请缩短后重试。": "Topics and messages support up to 4,000 characters. Shorten the text and retry.",
        "乌龟": "Turtles",
        "介词": "Prepositions",
        "以前的对话": "Conversation history",
        "你的英语学习伙伴": "Your English learning partner",
        "全部对话 · 累计学习记录": "All conversations · Learning history",
        "关闭菜单": "Close menu",
        "冠词": "Articles",
        "准确率": "Accuracy",
        "准确率 {0}，{1} 次机会": "Accuracy {0}, {1} opportunities",
        "准确率（%）": "Accuracy (%)",
        "分句数": "Clauses",
        "分析失败不会影响聊天，也不会计为语法错误。": "Analysis failures do not affect chat or count as grammar mistakes.",
        "切换到键盘会丢弃未发送的录音": "Switching to the keyboard discards the unsent recording",
        "动词时态": "Verb tense",
        "发送修改": "Send edit",
        "发送录音": "Send recording",
        "发送消息": "Send message",
        "发送系统消息": "Send system message",
        "取消系统消息": "Cancel system message",
        "句子已分析 {0} / {1} 次练习；分句已分析 {2} / {3} 次。平均值仅使用有分句分析的句子。": "Sentence analysis: {0} / {1} attempts. Clause analysis: {2} / {3}. Averages use only sentences with clause analysis.",
        "句子数": "Sentences",
        "向小聊发送系统消息": "Send a system message to XiaoLiao",
        "回复不完整，请重试。": "The reply is incomplete. Please retry.",
        "回复正在生成，请稍后重试。": "The reply is being generated. Please retry shortly.",
        "回复目标无效。": "The reply target is invalid.",
        "回复长度": "Reply length",
        "复杂": "Complex",
        "好": "OK",
        "学习统计": "Learning statistics",
        "学习进度": "Learning progress",
        "学习进度，全部对话的学习统计": "Learning progress, statistics for all conversations",
        "对话": "Conversation",
        "对话上下文过长。": "The conversation context is too long.",
        "对话伙伴正在回复": "Your conversation partner is replying",
        "对话伙伴的消息": "Partner's message",
        "对话伙伴的语音，{0}": "Partner's audio, {0}",
        "对话数据无效，操作未保存。": "Conversation data is invalid. The change was not saved.",
        "对话设置": "Conversation settings",
        "对话设置无效。": "Conversation settings are invalid.",
        "将下一条文字消息发给小聊系统；再次轻点取消。": "Send your next text message to the XiaoLiao system. Tap again to cancel.",
        "将在后续版本中提供": "Available in a future version",
        "将界面按钮、说明和错误信息显示为英语。": "Show interface controls, instructions and errors in English.",
        "小聊": "XiaoLiao",
        "小聊系统回复": "XiaoLiao system reply",
        "小聊系统正在回复": "The XiaoLiao system is replying",
        "尚无可用的评估结果": "No evaluation results yet",
        "已展开": "Expanded",
        "已收起": "Collapsed",
        "已有分析的累计结果": "Totals from available analysis",
        "已有学习记录仍被保留，请稍后重试。": "Your learning records are preserved. Please try again later.",
        "已评估 {0} / {1} 次练习；不确定的机会不计入准确率。": "Evaluated {0} / {1} attempts. Uncertain opportunities are excluded from accuracy.",
        "已达到测试请求限额，请稍后再试。": "The test request limit has been reached. Please try again later.",
        "已选择": "Selected",
        "帮我想个提示吧": "Suggest a prompt",
        "平均每句分句数": "Clauses per sentence",
        "开始新对话": "Start new conversation",
        "当前对话统计将在后续版本中提供": "Conversation-specific statistics are coming in a future version",
        "录音": "Record",
        "录音中 · {0}秒": "Recording · {0}s",
        "录音太短，请再试一次。": "The recording is too short. Please try again.",
        "录音已中断，未发送。请重新录制。": "Recording was interrupted and was not sent. Please record again.",
        "录音已停止，未发送。请重新录制。": "Recording stopped and was not sent. Please record again.",
        "录音文件暂不可用，无法转写。已有消息仍已保留。": "The recording is unavailable for transcription. Your message is preserved.",
        "录音时轻点结束采集，随后轻点播放或暂停试听；左侧按钮丢弃当前录音并重新录制": "Tap to end capture, then play or pause the take. The left button discards it and records again.",
        "录音未能保存，请重新录制。": "The recording could not be saved. Please record again.",
        "待分析 {0} 条 · 未完成 {1} 条": "Pending {0} · Unfinished {1}",
        "待发送": "Ready to send",
        "我发给小聊系统的消息": "My message to the XiaoLiao system",
        "我的消息": "My message",
        "打开菜单": "Open menu",
        "打开设置": "Open Settings",
        "指标": "Metric",
        "按首次使用时间记录，不代表刚刚学会。run、runs、running 分别统计。": "Recorded at first observed use, not when learned. run, runs and running count separately.",
        "播放": "Play",
        "播放录音": "Play recording",
        "播放进度{0}%": "Playback progress {0}%",
        "收到的回复无效，请重试。": "The reply is invalid. Please retry.",
        "数值": "Value",
        "新观察到的词汇": "Newly observed vocabulary",
        "新词数": "New words",
        "无法保存本地历史，操作尚未完成。请检查可用储存空间后重试；原有对话仍已保留。": "Local history could not be saved. Check available storage and retry. Your existing conversations are preserved.",
        "无法保存语法分析进度。消息已保留，请检查储存空间后重试分析。": "Grammar progress could not be saved. Your message is preserved. Check storage and retry analysis.",
        "无法开始录音。请检查麦克风是否可用，然后重试。": "Recording could not start. Check the microphone and try again.",
        "无法播放这段录音。请检查音频输出或重新录制。": "This recording could not be played. Check audio output or record again.",
        "无法朗读这条回复。请检查音频输出，然后轻点播放重试。文字回复仍已保留。": "This reply could not be read aloud. Check audio output and tap Play to retry. The text is preserved.",
        "无法读取本地历史。已有数据未被清除。请稍后重试。": "Local history could not be read. Your data has not been cleared. Please retry later.",
        "日期": "Date",
        "时态一致性": "Tense consistency",
        "时长未知": "Unknown duration",
        "暂不重试": "Not now",
        "暂停播放": "Pause playback",
        "暂停试听": "Pause preview",
        "暂无新词记录": "No new vocabulary yet",
        "暂无确定结果": "No scored results yet",
        "暂无该项的趋势数据": "No trend data for this category yet",
        "暂时无法处理这条消息。请调整内容。": "This message could not be processed. Please revise it.",
        "暂时无法读取统计": "Statistics are unavailable",
        "暂时无法转写这段录音。录音已保留，请重试。": "This recording could not be transcribed. The audio is preserved. Please retry.",
        "暂时还没有学习分析数据。这里会展示全部对话的学习记录。": "No learning analysis yet. Records from all conversations will appear here.",
        "最近": "Recent",
        "服务尚未配置完成。": "The service is not fully configured.",
        "服务暂不可用，请稍后重试。": "The service is unavailable. Please try again later.",
        "未选择": "Not selected",
        "本地历史": "Local history",
        "本地历史尚未打开，操作未保存。请重试读取历史。": "Local history is not open. The change was not saved. Please retry loading history.",
        "正在整理…": "Processing…",
        "正在整理学习记录…": "Preparing learning records…",
        "正在整理录音": "Processing recording",
        "正在请求麦克风权限": "Requesting microphone permission",
        "正在请求麦克风权限或整理录音，请稍候": "Requesting microphone permission or processing audio. Please wait.",
        "正在转写英语…首次使用可能需要下载识别模型。": "Transcribing English… First use may require a speech-model download.",
        "正在转写英语录音": "Transcribing English audio",
        "正式": "Formal",
        "此消息没有可播放的录音或可朗读的伙伴回复，或该操作暂不可用": "No playable recording or readable partner reply is available, or this action is unavailable",
        "此消息没有本地示例翻译": "No local sample translation is available for this message",
        "此设备暂不支持英语离线识别。请使用支持的 iPhone，或改用键盘输入。": "This device does not support offline English recognition. Use a supported device or type your message.",
        "每个窗口 {0} 个词。当天已分析词数不足时不显示分数；重复使用的词仍计入。": "Each window contains {0} words. Days with too few analyzed words have no score; repeated words still count.",
        "每日新观察到的词汇数量": "Daily newly observed vocabulary",
        "每日正确机会 ÷ 当日已确定结果的机会": "Daily correct opportunities ÷ daily scored opportunities",
        "没有识别到可用的英语语音。录音已保留，可以试听后重试或重新录制。": "No usable English speech was recognized. The recording is preserved. Preview it, retry or record again.",
        "测试访问凭证无效。": "The test access credential is invalid.",
        "消息无效，或消息过长（最多 4000 字符）。": "The message is invalid or exceeds 4,000 characters.",
        "温暖": "Warm",
        "点击横条，查看该项的每日准确率": "Tap a bar to view that category's daily accuracy",
        "用词难度": "Vocabulary difficulty",
        "看看你的英语进步": "See your English progress",
        "等待权限…": "Waiting for permission…",
        "简单": "Simple",
        "简短": "Brief",
        "系统消息仅支持文字，请先取消系统消息模式": "System messages are text-only. Exit system-message mode first.",
        "累计 MATTR {0}": "Overall MATTR {0}",
        "累计 MATTR —": "Overall MATTR —",
        "累计准确率 {0}": "Overall accuracy {0}",
        "练习量": "Practice activity",
        "结束录音，准备试听": "End capture and prepare to preview",
        "编辑": "Edit",
        "编辑消息": "Edit message",
        "网络连接失败或回复超时，请检查网络后重试。": "The connection failed or the reply timed out. Check your network and retry.",
        "翻译": "Translate",
        "聊天": "Chat",
        "聊天话题和场景": "Conversation topic and scenario",
        "聊聊天，练英语": "Chat and practice English",
        "联系小聊": "Message XiaoLiao",
        "联系推荐人": "Message the system",
        "英语朗读声音暂不可用。请在系统设置的辅助功能朗读设置中检查英语声音，然后重试。": "An English speaking voice is unavailable. Check English voices in the system accessibility speech settings, then retry.",
        "英语识别模型暂未就绪。首次使用需联网下载，请检查网络和储存空间后重试。": "The English speech model is not ready. First use requires a download. Check your network and storage, then retry.",
        "识别出的文字超过 4000 字符。录音已保留，请缩短后重新录制。": "The transcript exceeds 4,000 characters. The recording is preserved. Please record a shorter take.",
        "词数": "Words",
        "词数足够时显示多样性趋势": "Diversity trends appear when enough words are available",
        "词汇多样性": "Vocabulary diversity",
        "试听中": "Previewing",
        "语气": "Tone",
        "语法": "Grammar",
        "语法分析不完整或文本位置无效，请重试。": "Grammar analysis is incomplete or its text spans are invalid. Please retry.",
        "语法分析已达到测试限额，请稍后重试。": "The grammar-analysis test limit has been reached. Please retry later.",
        "语法分析暂不可用，请稍后重试。": "Grammar analysis is unavailable. Please try again later.",
        "语法分析请求无效或版本不受支持。": "The grammar request is invalid or its version is unsupported.",
        "语音": "Audio",
        "语音消息 · {0}": "Voice message · {0}",
        "语音消息，{0}": "Voice message, {0}",
        "请先发送或取消当前录音": "Send or cancel the current recording first",
        "请先处理当前录音或等待中的回复": "Finish the current recording or pending reply first",
        "请提供聊天话题和对话发生的实际场景，或点击按钮生成提示。": "Describe a conversation topic and scenario, or tap the suggestion button.",
        "请求必须使用 JSON。": "The request must use JSON.",
        "请求无效。": "The request is invalid.",
        "请求无效，或对话主题过长（最多 4000 字符）。": "The request is invalid or the topic exceeds 4,000 characters.",
        "请求过长。": "The request is too large.",
        "请等待回复，或处理失败的请求后继续": "Wait for the reply or resolve the failed request to continue",
        "请输入消息，并等待当前回复完成后发送": "Enter a message and wait for the current reply before sending",
        "转写": "Transcript",
        "转写尚未完成，录音已保留，可以重试。": "Transcription did not finish. The recording is preserved. You can retry.",
        "转写已中断，录音已保留。请重试。": "Transcription was interrupted. The recording is preserved. Please retry.",
        "轻松聊天，慢慢进步": "Chat comfortably, improve steadily",
        "轻点开始录音；录音时可暂停试听或发送": "Tap to start recording, then end capture to preview or send",
        "轻点显示或隐藏消息操作": "Tap to show or hide message actions",
        "轻点查看这一项的准确率趋势": "Tap to view this category's accuracy trend",
        "输入消息": "Enter a message",
        "返回语音输入": "Switch to voice input",
        "连续记录": "Continuous records",
        "部分录音文件暂不可用。对话文字和设置仍已保留。": "Some recording files are unavailable. Conversation text and settings are preserved.",
        "重新录音": "Restart recording",
        "重新生成": "Regenerate",
        "重试": "Retry",
        "重试内容与原请求不同。": "The retry differs from the original request.",
        "重试语法分析": "Retry grammar analysis",
        "重试读取": "Retry loading",
        "键盘输入": "Type a message",
        "随意": "Casual",
        "需要麦克风权限才能录音。请在系统设置中允许小聊使用麦克风。": "Microphone permission is required. Allow XiaoLiao to use the microphone in Settings.",
        "音频": "Audio",
        "首次在你的练习中出现的词形 · 按日统计": "Word forms first seen in your practice · Daily totals",
    ]
}

nonisolated private struct AppStringsKey: EnvironmentKey {
    static let defaultValue = AppStrings()
}

extension EnvironmentValues {
    var appStrings: AppStrings {
        get { self[AppStringsKey.self] }
        set { self[AppStringsKey.self] = newValue }
    }
}

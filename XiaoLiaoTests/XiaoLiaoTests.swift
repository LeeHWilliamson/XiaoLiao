import XCTest
@testable import XiaoLiao

final class XiaoLiaoTests: XCTestCase {
    func testGradingModeIsAnExplicitPresentationChoice() {
        let chinese = AppStrings()
        let english = AppStrings(isEnglish: true)
        XCTAssertFalse(chinese.isEnglish)
        XCTAssertEqual(chinese("对话设置"), "对话设置")
        XCTAssertEqual(english("对话设置"), "Conversation settings")
        XCTAssertEqual(english("主谓一致"), "Subject–verb agreement")
        XCTAssertEqual(chinese("已选择"), "已选择")
        XCTAssertEqual(english("已选择"), "Selected")
        XCTAssertTrue(chinese.locale.identifier.hasPrefix("zh"))
        XCTAssertTrue(english.locale.identifier.hasPrefix("en"))
    }

    func testDynamicCopyPreservesCountsAndUserTitles() {
        let english = AppStrings(isEnglish: true)
        XCTAssertEqual(english("已评估 3 / 7 次练习；不确定的机会不计入准确率。"),
                       "Evaluated 3 / 7 attempts. Uncertain opportunities are excluded from accuracy.")
        XCTAssertEqual(english("待分析 2 条 · 未完成 1 条"), "Pending 2 · Unfinished 1")
        XCTAssertEqual(english("动词时态"), "Verb tense")
        XCTAssertEqual(english("\(english("动词时态")) · 趋势"), "Verb tense · Trend")
        XCTAssertEqual(english("我的 {1} 🐢 主题的对话统计"), "Statistics for 我的 {1} 🐢 主题")
        XCTAssertEqual(english("语音消息 · \(english("3秒"))"), "Voice message · 3s")
        XCTAssertEqual(english("Unchanged content"), "Unchanged content")
        XCTAssertEqual(english("我想练习英语。"), "我想练习英语。")
    }

    func testSavedErrorsTranslateWhenRenderedWithoutRewritingTheirSource() {
        let savedError = "测试访问凭证无效。"
        let english = AppStrings(isEnglish: true)
        XCTAssertEqual(english.error(savedError), "The test access credential is invalid.")
        XCTAssertEqual(AppStrings().error(savedError), savedError)
        for error in [ConversationReplyError.notConfigured.localizedDescription,
                      ConversationReplyError.unavailable.localizedDescription,
                      SpeechTranscriptionError.modelUnavailable.localizedDescription,
                      "无法保存语法分析进度。消息已保留，请检查储存空间后重试分析。"] {
            let translated = english.error(error)
            XCTAssertNotEqual(translated, error)
            XCTAssertNotEqual(translated, "Something went wrong. Please try again.")
            XCTAssertNil(translated.range(of: "\\p{Han}", options: .regularExpression))
        }
    }

    func testUnknownServerFailuresHaveAnEnglishFallback() {
        let english = AppStrings(isEnglish: true)
        XCTAssertEqual(english.error("尚未收录的新服务错误。"), "Something went wrong. Please try again.")
        XCTAssertEqual(english.error("等待服务 3秒"), "Something went wrong. Please try again.")
        XCTAssertEqual(english.error("Not found"), "Not found")
        XCTAssertEqual(english.error(""), "")
        XCTAssertEqual(AppStrings().error("尚未收录的新服务错误。"), "尚未收录的新服务错误。")
    }
}

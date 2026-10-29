//
//  XiaoLiaoApp.swift
//  XiaoLiao
//
//  Created by user299515 on 10/26/26.
//

import SwiftUI

@main
struct XiaoLiaoApp: App {
    @State private var conversation = Self.makeConversation()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: conversation)
        }
    }

    private static func makeConversation() -> ConversationViewModel {
        #if DEBUG
        if let testID = ProcessInfo.processInfo.environment["XIAOLIAO_UI_TEST_STORE"], UUID(uuidString: testID) != nil {
            if ProcessInfo.processInfo.environment["XIAOLIAO_UI_TEST_STATS_FIXTURE"] == "1" {
                return ConversationViewModel(history: StatisticsPreviewData.sessions)
            }
            let directory = URL.applicationSupportDirectory
                .appendingPathComponent("XiaoLiaoUITests", isDirectory: true)
                .appendingPathComponent(testID, isDirectory: true)
            return .persistent(directory: directory)
        }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            // A unit-test host must not resume real history/recognition/provider jobs.
            return ConversationViewModel(history: [])
        }
        #endif
        let service = ConversationReplyService.configured()
        return .persistent(replyGenerator: { request in try await service.respond(to: request) },
                           grammarEvaluator: { request in try await service.evaluateGrammar(request) },
                           audioTranscriber: { clip in try await LocalSpeechTranscriber.transcribe(clip) })
    }
}

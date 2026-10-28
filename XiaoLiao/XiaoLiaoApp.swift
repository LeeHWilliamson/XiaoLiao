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
            let directory = URL.applicationSupportDirectory
                .appendingPathComponent("XiaoLiaoUITests", isDirectory: true)
                .appendingPathComponent(testID, isDirectory: true)
            return .persistent(directory: directory)
        }
        #endif
        return .persistent()
    }
}

import SwiftUI
import AVFoundation
import Combine

struct ContentView: View {
    private enum Route: Hashable { case conversation, settings, statistics }
    @State private var path: [Route] = []
    @State private var conversation: ConversationViewModel
    @State private var isMenuPresented = false
    @AppStorage(AppLanguage.preferenceKey) private var gradingMode = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    private var strings: AppStrings { AppStrings(isEnglish: gradingMode) }

    init(viewModel: ConversationViewModel) {
        _conversation = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            navigation
                .allowsHitTesting(!isMenuPresented)
                .accessibilityHidden(isMenuPresented)

            if isMenuPresented {
                ConversationNavigationMenu(
                    sessions: conversation.history,
                    selectedSessionID: conversation.activeSessionID,
                    onSelect: { id in
                        if conversation.openConversation(id) {
                            path = [.conversation]
                            dismissMenu()
                        }
                    },
                    onNewConversation: {
                        // With menu-based navigation, this also returns from
                        // settings/statistics to an unfinished new-chat draft.
                        if conversation.activeSessionID != nil {
                            conversation.prepareNewConversation()
                        }
                        path = []
                        dismissMenu()
                    },
                    onSettings: showSettings,
                    onStatistics: showStatistics,
                    onDismiss: dismissMenu
                )
                .transition(.move(edge: .leading))
            }
        }
        // The supplied Figma frames define a light-only brand palette.
        .environment(\.appStrings, strings)
        .environment(\.locale, strings.locale)
        .preferredColorScheme(.light)
        .alert(strings("本地历史"), isPresented: Binding(
            get: { conversation.storageIssue != nil },
            set: { if !$0 { conversation.storageIssue = nil } }
        )) {
            if conversation.storageIssue?.canRetryLoading == true {
                Button(strings("重试读取")) {
                    conversation.storageIssue = nil
                    Task { @MainActor in
                        await Task.yield()
                        conversation.retryLoadingHistory()
                    }
                }
            }
            Button(strings("好"), role: .cancel) { conversation.storageIssue = nil }
        } message: {
            Text(strings.error(conversation.storageIssue?.message ?? ""))
        }
        .alert(strings("对话"), isPresented: Binding(
            get: { conversation.replyIssue != nil },
            set: { if !$0 { conversation.replyIssue = nil } }
        )) {
            Button(strings("好"), role: .cancel) { conversation.replyIssue = nil }
        } message: {
            Text(strings.error(conversation.replyIssue ?? ""))
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                conversation.audio.interrupt()
                conversation.interruptTranscription()
            }
            if phase == .active {
                conversation.retryPendingTextAnalyses()
                conversation.resumeQueuedGrammarEvaluations()
                conversation.resumeQueuedTranscriptions()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
            if let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
               AVAudioSession.InterruptionType(rawValue: raw) == .began {
                conversation.audio.interrupt()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
            if let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
               AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable {
                conversation.audio.interrupt()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereResetNotification)) { _ in
            conversation.audio.interrupt()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereLostNotification)) { _ in
            conversation.audio.interrupt()
        }
        .onChange(of: path) { previous, current in
            if current.isEmpty && previous.contains(.conversation) && conversation.activeSessionID != nil {
                conversation.prepareNewConversation()
            }
        }
    }

    private var navigation: some View {
        NavigationStack(path: $path) {
            NewConversationView(
                viewModel: conversation,
                onStart: {
                    if conversation.startConversation() {
                        path = [.conversation]
                    }
                },
                onMenu: presentMenu
            )
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .conversation:
                    ConversationFeedView(
                        viewModel: conversation,
                        onMenu: presentMenu
                    )
                case .settings:
                    ConversationSettingsView(viewModel: conversation, onMenu: presentMenu)
                case .statistics:
                    StatisticsDashboardView(conversation: conversation, onMenu: presentMenu)
                }
            }
        }
    }

    private func presentMenu() {
        conversation.leaveFeed()
        conversation.deselectMessage()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            isMenuPresented = true
        }
    }

    private func dismissMenu() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            isMenuPresented = false
        }
    }

    private func showSettings() {
        conversation.leaveFeed()
        conversation.deselectMessage()
        if path.last != .settings {
            path = conversation.activeSessionID == nil ? [.settings] : [.conversation, .settings]
        }
        dismissMenu()
    }

    private func showStatistics() {
        conversation.leaveFeed()
        conversation.deselectMessage()
        if path.last != .statistics {
            path = conversation.activeSessionID == nil ? [.statistics] : [.conversation, .statistics]
        }
        dismissMenu()
    }
}

#Preview {
    ContentView(viewModel: ConversationViewModel())
}

import SwiftUI
import AVFoundation
import Combine

struct ContentView: View {
    private enum Route: Hashable { case conversation, settings, statistics }
    @State private var path: [Route] = []
    @State private var conversation: ConversationViewModel
    @State private var isHistoryPresented = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    init(viewModel: ConversationViewModel) {
        _conversation = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            navigation
                .allowsHitTesting(!isHistoryPresented)
                .accessibilityHidden(isHistoryPresented)

            if isHistoryPresented {
                ConversationHistoryDrawer(
                    sessions: conversation.history,
                    selectedSessionID: conversation.activeSessionID,
                    onSelect: { id in
                        if conversation.openConversation(id) {
                            path = [.conversation]
                            dismissHistory()
                        }
                    },
                    onNewConversation: {
                        conversation.prepareNewConversation()
                        path = []
                        dismissHistory()
                    },
                    onDismiss: dismissHistory
                )
                .transition(.move(edge: .leading))
            }
        }
        // The supplied Figma frames define a light-only brand palette.
        .preferredColorScheme(.light)
        .alert("本地历史", isPresented: Binding(
            get: { conversation.storageIssue != nil },
            set: { if !$0 { conversation.storageIssue = nil } }
        )) {
            if conversation.storageIssue?.canRetryLoading == true {
                Button("重试读取") {
                    conversation.storageIssue = nil
                    Task { @MainActor in
                        await Task.yield()
                        conversation.retryLoadingHistory()
                    }
                }
            }
            Button("好", role: .cancel) { conversation.storageIssue = nil }
        } message: {
            Text(conversation.storageIssue?.message ?? "")
        }
        .alert("对话", isPresented: Binding(
            get: { conversation.replyIssue != nil },
            set: { if !$0 { conversation.replyIssue = nil } }
        )) {
            Button("好", role: .cancel) { conversation.replyIssue = nil }
        } message: {
            Text(conversation.replyIssue ?? "")
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
                onHistory: presentHistory,
                onSettings: showSettings,
                onStatistics: showStatistics
            )
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .conversation:
                    ConversationFeedView(
                        viewModel: conversation,
                        onHistory: presentHistory,
                        onSettings: showSettings,
                        onStatistics: showStatistics
                    )
                case .settings:
                    ConversationSettingsView(viewModel: conversation) {
                        if !path.isEmpty { path.removeLast() }
                    }
                case .statistics:
                    StatisticsDashboardView(conversation: conversation) {
                        if !path.isEmpty { path.removeLast() }
                    }
                }
            }
        }
    }

    private func presentHistory() {
        conversation.leaveFeed()
        conversation.deselectMessage()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            isHistoryPresented = true
        }
    }

    private func dismissHistory() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            isHistoryPresented = false
        }
    }

    private func showSettings() {
        conversation.leaveFeed()
        conversation.deselectMessage()
        path.append(.settings)
    }

    private func showStatistics() {
        conversation.leaveFeed()
        conversation.deselectMessage()
        path.append(.statistics)
    }
}

#Preview {
    ContentView(viewModel: ConversationViewModel())
}

import SwiftUI

struct ContentView: View {
    private enum Route: Hashable { case conversation, settings }
    @State private var path: [Route] = []
    @State private var conversation = ConversationViewModel()
    @State private var isHistoryPresented = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                onSettings: showSettings
            )
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .conversation:
                    ConversationFeedView(
                        viewModel: conversation,
                        onHistory: presentHistory,
                        onSettings: showSettings
                    )
                case .settings:
                    ConversationSettingsView(viewModel: conversation) {
                        if !path.isEmpty { path.removeLast() }
                    }
                }
            }
        }
    }

    private func presentHistory() {
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
        conversation.deselectMessage()
        path.append(.settings)
    }
}

#Preview {
    ContentView()
}

import SwiftUI

struct ContentView: View {
    private enum Route: Hashable { case conversation }
    @State private var path: [Route] = []
    @State private var conversation = ConversationViewModel()

    var body: some View {
        NavigationStack(path: $path) {
            NewConversationView(viewModel: conversation) {
                if conversation.startConversation() {
                    path.append(.conversation)
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .conversation:
                    ConversationFeedView(viewModel: conversation) {
                        path.removeAll()
                    }
                }
            }
        }
        // The supplied Figma frames define a light-only brand palette.
        .preferredColorScheme(.light)
    }
}

#Preview {
    ContentView()
}

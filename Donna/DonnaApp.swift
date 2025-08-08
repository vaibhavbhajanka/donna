import SwiftUI

@main
struct DonnaApp: App {
    @StateObject private var chatViewModel = ChatViewModel()
    @StateObject private var appState = AppState()

    init() {
        // Initialize optional file logging early
        AppLogger.shared.enableFileLogging()
        AppLogger.shared.info("App", "DonnaApp initialized")
    }

    var body: some Scene {
        WindowGroup {
            if appState.isPanelVisible {
                AssistantFloatingPanel()
                    .environmentObject(chatViewModel)
                    .environmentObject(appState)
            } else {
                ZStack(alignment: .topTrailing) {
                    Color.clear
                    Button("Show Panel") { appState.isPanelVisible = true }
                        .padding()
                }
                .frame(minWidth: 480, minHeight: 320)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            AppCommands(chatViewModel: chatViewModel, appState: appState)
        }
    }
}

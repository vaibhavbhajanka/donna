import SwiftUI

struct AppCommands: Commands {
    let chatViewModel: ChatViewModel
    let appState: AppState

    var body: some Commands {
        CommandMenu("Donna") {
            Button("Hide Panel") { appState.isPanelVisible = false }
                .keyboardShortcut(.escape, modifiers: [])

            Divider()

            Button("Clear Transcript") { chatViewModel.clearTranscript() }
                .keyboardShortcut("k", modifiers: .command)

            Button("Previous Prompt") { chatViewModel.navigateHistory(up: true) }
                .keyboardShortcut(.upArrow, modifiers: .command)

            Button("Next Prompt") { chatViewModel.navigateHistory(up: false) }
                .keyboardShortcut(.downArrow, modifiers: .command)

            Button("Send Prompt") { chatViewModel.sendCurrentPrompt() }
                .keyboardShortcut(.return, modifiers: .command)
        }
    }
}

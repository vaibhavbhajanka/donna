import SwiftUI

struct AssistantFloatingPanel: View {
    @EnvironmentObject private var viewModel: ChatViewModel
    @EnvironmentObject private var appState: AppState

    private var lastUserCommand: String {
        viewModel.messages.last(where: { $0.role == .user })?.content ?? viewModel.inputText
    }

    var body: some View {
        VStack(spacing: 12) {
            // Header: Big command text and toggle
            HStack(alignment: .top) {
                Text(lastUserCommand.isEmpty ? "Type a command…" : lastUserCommand)
                    .font(.system(size: 21, weight: .semibold))
                    .kerning(0.2)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: { appState.isPanelVisible.toggle() }) {
                    Image(systemName: appState.isPanelVisible ? "eye.slash" : "eye")
                        .imageScale(.large)
                        .foregroundStyle(.secondary)
                        .help(appState.isPanelVisible ? "Hide Panel (Esc)" : "Show Panel")
                }
                .buttonStyle(.plain)
            }

            if let plan = viewModel.planLine, !plan.isEmpty {
                Text(plan)
                    .font(.system(size: 13.5))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
                    .padding(.bottom, 4)
            }

            // Transcript (scrollable)
            AssistantResponseView(messages: viewModel.messages)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

            // Log area
            ActionLogView(entries: viewModel.actionLogs)
                .frame(maxWidth: .infinity)
                .frame(height: 130)
                .background(.thinMaterial.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Input
            AssistantInputView(text: $viewModel.inputText, onSend: viewModel.sendCurrentPrompt)
        }
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.08))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 8)
        .frame(minWidth: 720, idealWidth: 820, maxWidth: 860, minHeight: 520, idealHeight: 620, maxHeight: 740)
        .padding()
    }
}

struct AssistantFloatingPanel_Previews: PreviewProvider {
    static var previews: some View {
        AssistantFloatingPanel()
            .environmentObject(ChatViewModel())
            .environmentObject(AppState())
            .frame(width: 820, height: 620)
            .preferredColorScheme(.dark)
    }
}

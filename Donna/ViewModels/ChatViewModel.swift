import Foundation
import Combine

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }
    let id: UUID
    let role: Role
    var content: String

    init(id: UUID = UUID(), role: Role, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}

struct ActionLogEntry: Identifiable, Equatable {
    let id: UUID
    let text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

final class ChatViewModel: ObservableObject {
    // Transcript
    @Published private(set) var messages: [ChatMessage] = []
    @Published var inputText: String = ""

    // Planning line and logs
    @Published var planLine: String? = nil
    @Published private(set) var actionLogs: [ActionLogEntry] = []

    // Prompt history
    @Published private(set) var promptHistory: [String] = []
    private var historyIndex: Int? = nil

    // LLM
    private let llm: LLMService
    private var streamingTask: Task<Void, Never>? = nil
    
    init() {
        let envKey = Dotenv.get("OPENAI_API_KEY")
        let procKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        let apiKey = (envKey?.isEmpty == false ? envKey : nil) ?? (procKey?.isEmpty == false ? procKey : nil)
        if let apiKey = apiKey {
            self.llm = OpenAIService(apiKey: apiKey)
        } else {
            self.llm = LocalEchoLLMService()
        }
    }

    // MARK: - Intents

    func sendCurrentPrompt() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Record history
        promptHistory.append(trimmed)
        historyIndex = nil

        // Add user message
        messages.append(ChatMessage(role: .user, content: trimmed))

        // Build plan sentence (simple local template)
        planLine = buildPlanLine(from: trimmed)

        // Add initial logs
        if llm is OpenAIService {
            actionLogs.append(ActionLogEntry(text: "Using OpenAI (gpt-4o-mini) with streaming…"))
        } else {
            actionLogs.append(ActionLogEntry(text: "Using local echo LLM (demo)…"))
        }
        
        
        actionLogs.append(ActionLogEntry(text: "Thinking…"))
        actionLogs.append(ActionLogEntry(text: "Preparing response…"))

        // Add placeholder assistant message to stream into
        messages.append(ChatMessage(role: .assistant, content: ""))

        // Start streaming assistant response via LLM
        startAssistantStreamingResponse(for: trimmed)

        // Clear input
        inputText = ""
    }

    func clearTranscript() {
        streamingTask?.cancel()
        streamingTask = nil
        messages.removeAll()
        actionLogs.removeAll()
        planLine = nil
    }

    func navigateHistory(up: Bool) {
        guard !promptHistory.isEmpty else { return }
        if historyIndex == nil {
            historyIndex = promptHistory.count - 1
        } else {
            if up {
                historyIndex = max(0, (historyIndex ?? 0) - 1)
            } else {
                historyIndex = min(promptHistory.count - 1, (historyIndex ?? 0) + 1)
            }
        }
        if let idx = historyIndex, promptHistory.indices.contains(idx) {
            inputText = promptHistory[idx]
        }
    }

    // MARK: - Private

    private func buildPlanLine(from prompt: String) -> String {
        // Simple echo plan for UI demo only
        return "Now I’ll process: \"\(prompt)\" and then summarize the result."
    }

    private func startAssistantStreamingResponse(for prompt: String) {
        streamingTask?.cancel()
        actionLogs.append(ActionLogEntry(text: "Generating reply…"))

        streamingTask = Task { [weak self] in
            guard let self = self else { return }
            var assistantIndex: Int? = self.messages.lastIndex(where: { $0.role == .assistant })

            for await chunk in llm.streamResponse(for: prompt) {
                if Task.isCancelled { break }
                await MainActor.run {
                    if assistantIndex == nil {
                        assistantIndex = self.messages.lastIndex(where: { $0.role == .assistant })
                    }
                    guard let idx = assistantIndex else { return }
                    var msg = self.messages[idx]
                    msg.content.append(contentsOf: chunk)
                    self.messages[idx] = msg
                }
            }

            await MainActor.run {
                self.actionLogs.append(ActionLogEntry(text: "Done."))
            }
        }
    }
}

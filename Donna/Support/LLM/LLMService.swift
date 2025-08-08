import Foundation

protocol LLMService {
    /// Returns an async stream of response chunks (tokens or small strings)
    func streamResponse(for prompt: String) -> AsyncStream<String>
    /// Optional: Given a user prompt and available tool specs, propose a tool call with arguments.
    /// Return nil to indicate no tool should be called.
    func planToolCall(prompt: String, tools: [LLMToolSpec]) async -> PlannedToolCall?
}

// Describes a tool name and (optionally) a JSON Schema for its input arguments
struct LLMToolSpec {
    let name: String
    let schemaJSON: String?
}

// Result of tool planning
struct PlannedToolCall {
    let toolName: String
    let arguments: [String: Any]
}

extension LLMService {
    func planToolCall(prompt: String, tools: [LLMToolSpec]) async -> PlannedToolCall? { nil }
}

/// A purely local echo/template LLM that streams out a templated response
/// character-by-character. This keeps the app client-only for MVP.
struct LocalEchoLLMService: LLMService {
    func streamResponse(for prompt: String) -> AsyncStream<String> {
        let full = makeLocalAssistantResponse(for: prompt)
        let characters = Array(full)
        return AsyncStream { continuation in
            Task.detached(priority: .userInitiated) {
                for ch in characters {
                    if Task.isCancelled { break }
                    continuation.yield(String(ch))
                    try? await Task.sleep(nanoseconds: 20_000_000) // 20ms per char
                }
                continuation.finish()
            }
        }
    }

    private func makeLocalAssistantResponse(for prompt: String) -> String {
        """
        Here’s a quick plan for your request:
        1) Understand the intent of: "\(prompt)".
        2) Outline the steps to achieve it.
        3) Present the result clearly.

        Result:
        - I would start by breaking the task into smaller steps, then execute each step while reporting progress in the log area.
        """
    }
}

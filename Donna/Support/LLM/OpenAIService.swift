import Foundation

struct OpenAIService: LLMService {
    struct Configuration {
        let apiKey: String
        let model: String
        let baseURL: URL
        let temperature: Double
        let systemPrompt: String?

        init(apiKey: String, model: String = "gpt-4o-mini", baseURL: URL = URL(string: "https://api.openai.com/v1")!, temperature: Double = 0.2, systemPrompt: String? = nil) {
            self.apiKey = apiKey
            self.model = model
            self.baseURL = baseURL
            self.temperature = temperature
            self.systemPrompt = systemPrompt
        }
    }

    private let config: Configuration

    init(apiKey: String, model: String = "gpt-4o-mini", systemPrompt: String? = nil) {
        self.config = Configuration(apiKey: apiKey, model: model, systemPrompt: systemPrompt)
    }

    init(configuration: Configuration) {
        self.config = configuration
    }

    func streamResponse(for prompt: String) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task.detached(priority: .userInitiated) {
                do {
                    var request = URLRequest(url: config.baseURL.appendingPathComponent("chat/completions"))
                    request.httpMethod = "POST"
                    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.addValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
                    var messages: [OpenAIMessage] = []
                    if let system = config.systemPrompt, !system.isEmpty {
                        messages.append(OpenAIMessage(role: "system", content: system))
                    }
                    messages.append(OpenAIMessage(role: "user", content: prompt))
                    let body = OpenAIChatRequest(model: config.model, messages: messages, temperature: config.temperature, stream: true)
                    request.httpBody = try JSONEncoder().encode(body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                    guard http.statusCode == 200 else {
                        // Try to read error payload
                        var errorText = "OpenAI HTTP \(http.statusCode)"
                        if let data = try? await bytes.reduce(into: Data()) { partial, byte in partial.append(byte) } {
                            if let s = String(data: data, encoding: .utf8) { errorText += ": \(s)" }
                        }
                        continuation.yield("[OpenAI error] \(errorText)")
                        continuation.finish()
                        return
                    }

                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let jsonPart = String(line.dropFirst(6))
                            if jsonPart == "[DONE]" { break }
                            guard let data = jsonPart.data(using: .utf8) else { continue }
                            if let chunk = try? JSONDecoder().decode(OpenAIStreamChunk.self, from: data) {
                                let text = chunk.choices.first?.delta.content ?? ""
                                if !text.isEmpty { continuation.yield(text) }
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.yield("[OpenAI error] \(error.localizedDescription)")
                    continuation.finish()
                }
            }
        }
    }

    // Simple planner using the LLM itself. It sends a short instruction with available tools
    // and asks the model to return a tiny JSON plan {"tool":"name","args":{...}} or "null".
    func planToolCall(prompt: String, tools: [LLMToolSpec]) async -> PlannedToolCall? {
        // Build a compact tool list with schemas (if any)
        let toolList = tools.map { spec in
            if let schema = spec.schemaJSON, !schema.isEmpty {
                return "- \(spec.name): schema \(schema)"
            } else {
                return "- \(spec.name)"
            }
        }.joined(separator: "\n")

        let instruction = """
You are planning a single tool call for a macOS assistant using MCP.
Given the user prompt and available tools, decide if a tool should be called.
If yes, return ONLY a compact JSON object: {"tool":"<name>","args":{...}}.
If no, return null.

Available tools:\n\(toolList)

User: \(prompt)
"""

        // Use the same streaming endpoint but without streaming to get one small completion
        do {
            var request = URLRequest(url: config.baseURL.appendingPathComponent("chat/completions"))
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
            let body = OpenAIChatRequest(model: config.model, messages: [
                OpenAIMessage(role: "system", content: "Reply with only valid JSON or null."),
                OpenAIMessage(role: "user", content: instruction)
            ], temperature: 0, stream: false)
            request.httpBody = try JSONEncoder().encode(body)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            // Minimal parse to extract content
            struct OneShot: Decodable {
                struct Choice: Decodable {
                    struct Message: Decodable { let content: String }
                    let message: Message
                }
                let choices: [Choice]
            }
            if let decoded = try? JSONDecoder().decode(OneShot.self, from: data) {
                let content = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if content.lowercased() == "null" { return nil }
                // Try parse JSON {tool,args}
                if let cdata = content.data(using: .utf8),
                   let dict = try? JSONSerialization.jsonObject(with: cdata) as? [String: Any],
                   let tool = dict["tool"] as? String {
                    let args = dict["args"] as? [String: Any] ?? [:]
                    return PlannedToolCall(toolName: tool, arguments: args)
                }
            }
        } catch {
            return nil
        }
        return nil
    }
}

// MARK: - OpenAI API DTOs

private struct OpenAIChatRequest: Encodable {
    let model: String
    let messages: [OpenAIMessage]
    let temperature: Double
    let stream: Bool
}

private struct OpenAIMessage: Encodable {
    let role: String // "system" | "user" | "assistant"
    let content: String
}

private struct OpenAIStreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable { let content: String? }
        let index: Int
        let delta: Delta
        let finish_reason: String?
    }
    let id: String?
    let object: String?
    let model: String?
    let choices: [Choice]
}

import Foundation

struct OpenAIService: LLMService {
    struct Configuration {
        let apiKey: String
        let model: String
        let baseURL: URL
        let temperature: Double

        init(apiKey: String, model: String = "gpt-4o-mini", baseURL: URL = URL(string: "https://api.openai.com/v1")!, temperature: Double = 0.2) {
            self.apiKey = apiKey
            self.model = model
            self.baseURL = baseURL
            self.temperature = temperature
        }
    }

    private let config: Configuration

    init(apiKey: String, model: String = "gpt-4o-mini") {
        self.config = Configuration(apiKey: apiKey, model: model)
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

                    let body = OpenAIChatRequest(model: config.model, messages: [OpenAIMessage(role: "user", content: prompt)], temperature: config.temperature, stream: true)
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

import Foundation
import Combine
import MCP

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

@MainActor
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
    private var cancellables: Set<AnyCancellable> = []
    private var lastLoggedToolCount: Int = 0
    
    // MCP Integration
    let mcpManager: MCPManager
    
    init() {
        let envKey = Dotenv.get("OPENAI_API_KEY")
        let procKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        let apiKey = (envKey?.isEmpty == false ? envKey : nil) ?? (procKey?.isEmpty == false ? procKey : nil)
        if let apiKey = apiKey {
            let system = "You are Donna, a macOS assistant. When applicable, suggest or request using available MCP tools (Apple MCP: notes, contacts, calendar, mail, reminders). Prefer precise, concise answers."
            self.llm = OpenAIService(apiKey: apiKey, model: "gpt-4o-mini", systemPrompt: system)
        } else {
            self.llm = LocalEchoLLMService()
        }
        
        // Initialize MCP Manager
        self.mcpManager = MCPManager()
        AppLogger.shared.info("ChatVM", "initialized")
        
        // Servers are managed via MCPServerRegistry persistence; no sample servers
        AppLogger.shared.info("ChatVM", "Using persisted registry servers: \(mcpManager.servers.count)")
        
        // Start connecting to enabled MCP servers
        Task { @MainActor in
            AppLogger.shared.info("ChatVM", "Starting MCP server connections…")
            await mcpManager.connectToAllEnabledServers()
            AppLogger.shared.info("ChatVM", "MCP initialization complete")
        }

        // Observe MCP tool discovery and append to the in-app log continuously
        mcpManager.$availableTools
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tools in
                guard let self = self else { return }
                if tools.count != self.lastLoggedToolCount {
                    self.lastLoggedToolCount = tools.count
                    let names = tools.map { $0.name }.joined(separator: ", ")
                    self.actionLogs.append(ActionLogEntry(text: "MCP tools (\(tools.count)): \(names)"))
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Intents

    func sendCurrentPrompt() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Built-in command: show tools
        let lower = trimmed.lowercased()
        if lower == "/tools" || lower == "list tools" || lower == "show tools" {
            showAvailableTools()
            inputText = ""
            return
        }
        // Built-in command: call a tool directly
        if lower.hasPrefix("/call ") {
            handleDirectToolCall(command: trimmed)
            inputText = ""
            return
        }
        // Built-in command: show tool schema
        if lower.hasPrefix("/schema ") {
            handleSchemaCommand(command: trimmed)
            inputText = ""
            return
        }

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
        
        // Add MCP status to logs
        let connectedServers = mcpManager.serverStatuses.values.filter { $0.status == .connected }.count
        let totalServers = mcpManager.servers.count
        if totalServers > 0 {
            actionLogs.append(ActionLogEntry(text: "MCP servers: \(connectedServers)/\(totalServers) connected"))
            if connectedServers > 0 {
                let availableToolsCount = mcpManager.availableTools.count
                actionLogs.append(ActionLogEntry(text: "Available MCP tools: \(availableToolsCount)"))
            }
        }
        
        actionLogs.append(ActionLogEntry(text: "Thinking…"))
        actionLogs.append(ActionLogEntry(text: "Preparing response…"))

        // Add placeholder assistant message to stream into
        messages.append(ChatMessage(role: .assistant, content: ""))

        // If MCP tools available, attempt LLM-driven tool planning first; fall back to heuristics
        Task { @MainActor in
            var handled = false
            if !self.mcpManager.availableTools.isEmpty {
                // Build tool specs for planner
                let specs: [LLMToolSpec] = self.mcpManager.availableTools.map { t in
                    var schemaJSON: String? = nil
                    if let schema = t.inputSchema, let data = try? JSONEncoder().encode(schema), let json = String(data: data, encoding: .utf8) {
                        schemaJSON = json
                    }
                    return LLMToolSpec(name: t.name, schemaJSON: schemaJSON)
                }
                if let plan = await self.llm.planToolCall(prompt: trimmed, tools: specs) {
                    if let tool = self.mcpManager.availableTools.first(where: { $0.name == plan.toolName }) {
                        self.actionLogs.append(ActionLogEntry(text: "Calling MCP tool (planned): \(tool.name)"))
                        do {
                            let res = try await self.mcpManager.callTool(tool, parameters: plan.arguments)
                            let text = res.content ?? res.error ?? ""
                            self.appendToolResultToUI(text: text)
                            handled = true
                        } catch {
                            let err = "MCP tool error: \(error.localizedDescription)"
                            self.actionLogs.append(ActionLogEntry(text: err))
                            self.appendToolResultToUI(text: err)
                            handled = true
                        }
                    }
                }
            }
            if !handled {
                handled = await self.tryCallMCPToolIfApplicable(for: trimmed)
            }
            if !handled {
                self.startAssistantStreamingResponse(for: trimmed)
            }
        }

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
    
    private func addSampleMCPServers() { /* removed */ }

    private func buildPlanLine(from prompt: String) -> String {
        // Simple echo plan for UI demo only
        return "Now I'll process: \"\(prompt)\" and then summarize the result."
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

    // MARK: - Simple MCP tool router (heuristic)
    private func tryCallMCPToolIfApplicable(for prompt: String) async -> Bool {

        let normalized = prompt.lowercased()
        let tools = mcpManager.availableTools
        guard !tools.isEmpty else { return false }

        // Build fuzzy candidates by keyword
        var desiredNames: [String] = []
        if normalized.contains("note") {
            desiredNames += [
                "notes.list", "list_notes", "notes.list_notes",
                "notes.search", "search_notes"
            ]
        } else if normalized.contains("contact") {
            desiredNames += ["contacts.list", "list_contacts", "contacts.search", "search_contacts"]
        } else if normalized.contains("calendar") || normalized.contains("event") {
            desiredNames += ["calendar.list", "list_events", "calendar.search", "search_events"]
        } else if normalized.contains("reminder") {
            desiredNames += ["reminders.list", "list_reminders", "reminders.search", "search_reminders"]
        } else if normalized.contains("mail") || normalized.contains("email") {
            desiredNames += ["mail.list", "list_mail", "mail.search", "search_mail"]
        }

        // Pick a tool by exact candidate name, else fuzzy contains both keywords
        var selected: MCPTool?
        selected = tools.first(where: { desiredNames.contains($0.name) })
        if selected == nil, normalized.contains("note") {
            selected = tools.first(where: { $0.name.lowercased().contains("note") && ($0.name.lowercased().contains("list") || $0.inputSchema == nil) })
        }
        if selected == nil {
            // If there is a generic 'notes' tool, try it with a fallback action
            if normalized.contains("note"), let notesTool = tools.first(where: { $0.name.lowercased() == "notes" }) {
                selected = notesTool
            } else {
                return false
            }
        }

        actionLogs.append(ActionLogEntry(text: "Calling MCP tool: \(selected!.name)"))

        // Minimal query extraction for *search* tools
        var params: [String: Any] = [:]
        if selected!.name.lowercased().contains("search") {
            let stripped = normalized
                .replacingOccurrences(of: "search", with: "")
                .replacingOccurrences(of: "notes", with: "")
                .replacingOccurrences(of: "note", with: "")
                .replacingOccurrences(of: "for", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !stripped.isEmpty { params["query"] = stripped }
        } else if selected!.name.lowercased() == "notes" {
            // Heuristic: if the tool is a generic notes tool, try common action keys
            if containsAny(normalized, ["list","show","all","display","see"]) {
                if let resultText = await callWithFallbackActionKeys(tool: selected!, action: "list") {
                    appendToolResultToUI(text: resultText)
                    return true
                }
            } else if containsAny(normalized, ["search","find","look for"]) {
                // Extract a naive query
                let query = extractSearchQuery(from: prompt, keywords: ["search","find","look for","for","notes","note","my"]) ?? ""
                if !query.isEmpty, let resultText = await callWithFallbackActionKeys(tool: selected!, action: "search", extras: ["searchText": query]) {
                    appendToolResultToUI(text: resultText)
                    return true
                }
            } else if containsAny(normalized, ["create","add","new note","make a note","make note"]) {
                let (title, body) = extractCreateNoteFields(from: prompt)
                var extras: [String: Any] = ["title": title, "body": body]
                if let folder = extractFolderName(from: prompt) { extras["folderName"] = folder }
                if let resultText = await callWithFallbackActionKeys(tool: selected!, action: "create", extras: extras) {
                    appendToolResultToUI(text: resultText)
                    return true
                }
            }
        }

        do {
            let result = try await mcpManager.callTool(selected!, parameters: params)
            let text = result.content ?? result.error ?? ""
            appendToolResultToUI(text: text)
            return true
        } catch {
            let err = "MCP tool error: \(error.localizedDescription)"
            actionLogs.append(ActionLogEntry(text: err))
            appendToolResultToUI(text: err)
            return true
        }
    }

    // MARK: - Utilities
    private func showAvailableTools() {
        let tools = mcpManager.availableTools
        if tools.isEmpty {
            actionLogs.append(ActionLogEntry(text: "No MCP tools available yet (server still initializing)."))
            return
        }
        let lines = tools.map { t in
            let argHint = t.inputSchema == nil ? "[no args]" : "[args]"
            return "- \(t.name) — \(t.description ?? "") \(argHint)"
        }
        let header = "Available MCP tools (\(tools.count)):\n" + lines.joined(separator: "\n")
        actionLogs.append(ActionLogEntry(text: header))
        if let idx = messages.lastIndex(where: { $0.role == .assistant }) {
            var msg = messages[idx]
            msg.content = msg.content.isEmpty ? header : (msg.content + "\n\n" + header)
            messages[idx] = msg
        } else {
            messages.append(ChatMessage(role: .assistant, content: header))
        }
        actionLogs.append(ActionLogEntry(text: "Tip: use '/call <toolName> {jsonArgs}' to invoke directly (e.g., /call notes {\"operation\":\"list\"}). Use '/schema <toolName>' to view argument schema."))
    }

    private func handleDirectToolCall(command: String) {
        // Format: /call <toolName> [json-args]
        let tokens = command.dropFirst(6) // remove '/call '
        let parts = tokens.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard !parts.isEmpty else {
            actionLogs.append(ActionLogEntry(text: "Usage: /call <toolName> {jsonArgs}"))
            return
        }
        let toolName = String(parts[0])
        let jsonArg = parts.count > 1 ? String(parts[1]) : nil
        let tools = mcpManager.availableTools
        guard let tool = tools.first(where: { $0.name == toolName }) else {
            actionLogs.append(ActionLogEntry(text: "Tool not found: \(toolName)"))
            return
        }
        var params: [String: Any] = [:]
        if let jsonArg, let data = jsonArg.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            params = obj
        }
        actionLogs.append(ActionLogEntry(text: "Calling MCP tool: \(tool.name) with args: \(params)"))
        Task { @MainActor in
            do {
                let res = try await mcpManager.callTool(tool, parameters: params)
                let text = res.content ?? res.error ?? ""
                actionLogs.append(ActionLogEntry(text: text))
                if let idx = messages.lastIndex(where: { $0.role == .assistant }) {
                    var msg = messages[idx]
                    msg.content = msg.content.isEmpty ? text : (msg.content + "\n\n" + text)
                    messages[idx] = msg
                } else {
                    messages.append(ChatMessage(role: .assistant, content: text))
                }
            } catch {
                let err = "MCP tool error: \(error.localizedDescription)"
                actionLogs.append(ActionLogEntry(text: err))
                if let idx = messages.lastIndex(where: { $0.role == .assistant }) {
                    var msg = messages[idx]
                    msg.content = msg.content.isEmpty ? err : (msg.content + "\n\n" + err)
                    messages[idx] = msg
                } else {
                    messages.append(ChatMessage(role: .assistant, content: err))
                }
            }
        }
    }

    // MARK: - Schema & Helpers
    private func handleSchemaCommand(command: String) {
        // Format: /schema <toolName>
        let tokens = command.dropFirst(8) // remove '/schema '
        let toolName = tokens.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !toolName.isEmpty else {
            actionLogs.append(ActionLogEntry(text: "Usage: /schema <toolName>"))
            return
        }
        let tools = mcpManager.availableTools
        guard let tool = tools.first(where: { $0.name == toolName }) else {
            actionLogs.append(ActionLogEntry(text: "Tool not found: \(toolName)"))
            return
        }
        let schemaText: String
        if let schema = tool.inputSchema, let data = try? JSONEncoder().encode(schema), let json = String(data: data, encoding: .utf8) {
            schemaText = json
        } else if tool.inputSchema != nil {
            schemaText = String(describing: tool.inputSchema!)
        } else {
            schemaText = "No input schema for tool \(tool.name)."
        }
        let text = "Schema for \(tool.name):\n\(schemaText)"
        actionLogs.append(ActionLogEntry(text: text))
        if let idx = messages.lastIndex(where: { $0.role == .assistant }) {
            var msg = messages[idx]
            msg.content = msg.content.isEmpty ? text : (msg.content + "\n\n" + text)
            messages[idx] = msg
        } else {
            messages.append(ChatMessage(role: .assistant, content: text))
        }
    }

    private func appendToolResultToUI(text: String) {
        let snippet = String(text.prefix(1200))
        actionLogs.append(ActionLogEntry(text: snippet))
        if let idx = messages.lastIndex(where: { $0.role == .assistant }) {
            var msg = messages[idx]
            msg.content = msg.content.isEmpty ? snippet : (msg.content + "\n\n" + snippet)
            messages[idx] = msg
        } else {
            messages.append(ChatMessage(role: .assistant, content: snippet))
        }
    }

    private func callWithFallbackActionKeys(tool: MCPTool, action: String, extras: [String: Any] = [:]) async -> String? {
        // Prefer the schema-indicated key name 'operation' first
        let candidateKeys = ["operation", "action", "method", "cmd"]
        for key in candidateKeys {
            do {
                var params: [String: Any] = [key: action]
                extras.forEach { params[$0.key] = $0.value }
                let result = try await mcpManager.callTool(tool, parameters: params)
                if result.isSuccess {
                    return result.content ?? ""
                }
                // If not success, try next key
            } catch {
                // try next key
            }
        }
        return nil
    }

    // Very small helpers for intent parsing
    private func containsAny(_ text: String, _ keywords: [String]) -> Bool {
        for k in keywords { if text.contains(k) { return true } }
        return false
    }

    private func extractSearchQuery(from prompt: String, keywords: [String]) -> String? {
        var q = prompt
        for k in keywords { q = q.replacingOccurrences(of: k, with: "", options: .caseInsensitive) }
        q = q.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty ? nil : q
    }

    private func extractCreateNoteFields(from prompt: String) -> (String, String) {
        // Very naive: try to use quoted text as title, remainder as body; else first clause as title
        if let firstQuote = prompt.firstIndex(of: "\""), let lastQuote = prompt.lastIndex(of: "\""), firstQuote != lastQuote {
            let title = String(prompt[prompt.index(after: firstQuote)..<lastQuote]).trimmingCharacters(in: .whitespacesAndNewlines)
            let body = prompt.replacingOccurrences(of: "\"\(title)\"", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            return (title.isEmpty ? "New Note" : title, body)
        }
        // Else split by ' - ' as a simple separator
        let parts = prompt.components(separatedBy: " - ")
        if parts.count >= 2 {
            let title = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "New Note"
            let body = parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespacesAndNewlines)
            return (title.isEmpty ? "New Note" : title, body)
        }
        // Fallback: use entire prompt as body
        return ("New Note", prompt)
    }

    private func extractFolderName(from prompt: String) -> String? {
        // Look for 'in <folder>'
        let lower = prompt.lowercased()
        guard let range = lower.range(of: " in ") else { return nil }
        let after = prompt[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        if after.isEmpty { return nil }
        // Stop at common trailing words
        let stops = [" called ", " titled ", " named ", ".", ","]
        var folder = String(after)
        for stop in stops {
            if let r = folder.range(of: stop, options: .caseInsensitive) {
                folder = String(folder[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return folder.isEmpty ? nil : folder
    }
}

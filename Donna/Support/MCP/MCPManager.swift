import Foundation
import MCP

struct MCPPrompt: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let description: String?
    let arguments: [String]?
    let serverId: UUID
    
    init(id: String, name: String, description: String? = nil, arguments: [String]? = nil, serverId: UUID) {
        self.id = id
        self.name = name
        self.description = description
        self.arguments = arguments
        self.serverId = serverId
    }
}

@MainActor
final class MCPManager: ObservableObject {
    @Published private(set) var servers: [MCPServer] = []
    @Published private(set) var serverStatuses: [UUID: MCPServerStatus] = [:]
    @Published private(set) var availableTools: [MCPTool] = []
    @Published private(set) var availableResources: [MCPResource] = []
    @Published private(set) var availablePrompts: [MCPPrompt] = []
    @Published private(set) var isInitialized = false
    
    private var clients: [UUID: Client] = [:]
    private var serverRegistry: MCPServerRegistry
    private let transportFactory: MCPTransportFactory
    
    init() {
        self.serverRegistry = MCPServerRegistry()
        self.transportFactory = MCPTransportFactory()
        loadServers()
    }
    
    // MARK: - Server Management
    
    func addServer(_ server: MCPServer) {
        servers.append(server)
        serverStatuses[server.id] = MCPServerStatus(serverId: server.id, status: .disconnected)
        saveServers()
        
        if server.isEnabled {
            Task {
                await connectToServer(server)
            }
        }
    }
    
    func removeServer(_ server: MCPServer) {
        servers.removeAll { $0.id == server.id }
        serverStatuses.removeValue(forKey: server.id)
        clients.removeValue(forKey: server.id)
        availableTools.removeAll { $0.serverId == server.id }
        availableResources.removeAll { $0.serverId == server.id }
        availablePrompts.removeAll { $0.serverId == server.id }
        saveServers()
    }
    
    func updateServerStatus(_ serverId: UUID, status: MCPConnectionStatus, error: String? = nil) {
        let connectedAt = status == .connected ? Date() : serverStatuses[serverId]?.connectedAt
        serverStatuses[serverId] = MCPServerStatus(
            serverId: serverId,
            status: status,
            lastError: error,
            connectedAt: connectedAt
        )
    }
    
    // MARK: - Connection Management
    
    func connectToAllEnabledServers() async {
        AppLogger.shared.info("MCPManager", "Starting connection to all enabled servers")
        AppLogger.shared.info("MCPManager", "Total servers: \(servers.count)")
        
        let enabledServers = servers.filter(\.isEnabled)
        AppLogger.shared.info("MCPManager", "Enabled servers: \(enabledServers.count)")
        
        for (index, server) in enabledServers.enumerated() {
            AppLogger.shared.info("MCPManager", "Connecting to server \(index + 1)/\(enabledServers.count): \(server.name)")
            await connectToServer(server)
        }
        
        isInitialized = true
        AppLogger.shared.info("MCPManager", "Initialization complete. Connected servers: \(clients.count)/\(enabledServers.count)")
    }
    
    func connectToServer(_ server: MCPServer) async {
        updateServerStatus(server.id, status: .connecting)
        
        do {
            AppLogger.shared.info("MCPManager", "Connecting to MCP server: \(server.name)")
            AppLogger.shared.debug("MCPManager", "Server URL: \(server.url)")
            
            let client = Client(name: "Donna", version: "0.1.0")
            let transport = try transportFactory.createTransport(for: server)
            
            AppLogger.shared.debug("MCPManager", "Attempting client connection…")
            try await client.connect(transport: transport)
            clients[server.id] = client
            
            AppLogger.shared.info("MCPManager", "Connected successfully to \(server.name)")
            updateServerStatus(server.id, status: .connected)
            await discoverServerCapabilities(server)
            
        } catch {
            AppLogger.shared.error("MCPManager", "Connection failed to \(server.name): \(error.localizedDescription)")
            updateServerStatus(server.id, status: .error, error: error.localizedDescription)
        }
    }
    
    func disconnectFromServer(_ server: MCPServer) {
        clients.removeValue(forKey: server.id)
        updateServerStatus(server.id, status: .disconnected)
        availableTools.removeAll { $0.serverId == server.id }
        availableResources.removeAll { $0.serverId == server.id }
        availablePrompts.removeAll { $0.serverId == server.id }
    }
    
    private func discoverServerCapabilities(_ server: MCPServer) async {
        guard let client = clients[server.id] else { return }
        
        // Discover tools
        do {
            let (tools, _) = try await client.listTools()
            let mcpTools = tools.map { tool in
                MCPTool(
                    id: tool.name,
                    name: tool.name,
                    description: tool.description,
                    inputSchema: tool.inputSchema,
                    serverId: server.id
                )
            }
            availableTools.append(contentsOf: mcpTools)
            AppLogger.shared.info("MCPManager", "Discovered tools (\(mcpTools.count)): \(mcpTools.map{ $0.name }.joined(separator: ", "))")
        } catch {
            AppLogger.shared.warn("MCPManager", "listTools failed: \(error.localizedDescription)")
        }

        // Discover resources (optional; gracefully handle if not supported)
        do {
            let (resources, _) = try await client.listResources()
            let mcpResources = resources.map { resource in
                MCPResource(
                    id: resource.uri,
                    uri: resource.uri,
                    name: resource.name,
                    description: resource.description,
                    mimeType: resource.mimeType,
                    serverId: server.id
                )
            }
            availableResources.append(contentsOf: mcpResources)
            AppLogger.shared.info("MCPManager", "Discovered resources (\(mcpResources.count))")
        } catch {
            let errorMsg = error.localizedDescription.lowercased()
            if errorMsg.contains("method not found") || errorMsg.contains("not implemented") {
                AppLogger.shared.debug("MCPManager", "Server '\(server.name)' does not support resources (optional MCP feature)")
            } else {
                AppLogger.shared.warn("MCPManager", "listResources failed: \(error.localizedDescription)")
            }
        }
        
        // Discover prompts (optional; gracefully handle if not supported)
        do {
            let (prompts, _) = try await client.listPrompts()
            let mcpPrompts = prompts.map { prompt in
                MCPPrompt(
                    id: prompt.name,
                    name: prompt.name,
                    description: prompt.description,
                    arguments: prompt.arguments?.map { $0.name },
                    serverId: server.id
                )
            }
            availablePrompts.append(contentsOf: mcpPrompts)
            AppLogger.shared.info("MCPManager", "Discovered prompts (\(mcpPrompts.count)): \(mcpPrompts.map{ $0.name }.joined(separator: ", "))")
        } catch {
            let errorMsg = error.localizedDescription.lowercased()
            if errorMsg.contains("method not found") || errorMsg.contains("not implemented") {
                AppLogger.shared.debug("MCPManager", "Server '\(server.name)' does not support prompts (optional MCP feature)")
            } else {
                AppLogger.shared.warn("MCPManager", "listPrompts failed: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Tool Execution
    
    func callTool(_ tool: MCPTool, parameters: [String: Any]) async throws -> MCPToolResult {
        guard let client = clients[tool.serverId] else {
            throw MCPError.serverNotConnected
        }
        
        let callId = UUID()
        
        do {
            // Convert [String: Any] to [String: Value] for MCP SDK
            var arguments: [String: Value]? = nil
            if !parameters.isEmpty {
                arguments = Dictionary(uniqueKeysWithValues: parameters.compactMap { (key, value) in
                    if let stringValue = value as? String {
                        return (key, Value.string(stringValue))
                    } else if let intValue = value as? Int {
                        return (key, Value.int(intValue))
                    } else if let doubleValue = value as? Double {
                        return (key, Value.double(doubleValue))
                    } else if let boolValue = value as? Bool {
                        return (key, Value.bool(boolValue))
                    }
                    return nil
                })
            }
            
            let (content, isError) = try await client.callTool(name: tool.name, arguments: arguments)
            
            let contentString = content.compactMap { item in
                switch item {
                case .text(let text):
                    return text
                case .image(_, let mimeType, let metadata):
                    return metadata?["alt"] ?? "[Image: \(mimeType)]"
                case .audio(_, let mimeType):
                    return "[Audio: \(mimeType)]"
                case .resource(let uri, _, let text):
                    return text ?? "[Resource: \(uri)]"
                }
            }.joined(separator: "\n")
            
            return MCPToolResult(
                callId: callId,
                isSuccess: !(isError ?? false),
                content: (isError ?? false) ? nil : contentString,
                error: (isError ?? false) ? contentString : nil
            )
            
        } catch {
            return MCPToolResult(
                callId: callId,
                isSuccess: false,
                error: error.localizedDescription
            )
        }
    }
    
    // MARK: - Resource Access
    
    func readResource(_ resource: MCPResource) async throws -> MCPResourceContent {
        guard let client = clients[resource.serverId] else {
            throw MCPError.serverNotConnected
        }
        
        let contents = try await client.readResource(uri: resource.uri)
        // Resource contents are returned as Resource.Content structs, not enums
        let contentString = contents.compactMap { resourceContent in
            if let text = resourceContent.text {
                return text
            } else if let blob = resourceContent.blob {
                return "[Binary data: \(blob.count) characters]"
            } else {
                return "[Resource: \(resourceContent.uri)]"
            }
        }.joined(separator: "\n")
        
        return MCPResourceContent(
            resourceId: resource.id,
            content: contentString,
            mimeType: resource.mimeType
        )
    }
    
    // MARK: - Prompt Access
    
    func getPrompt(name: String, arguments: [String: Any] = [:]) async throws -> String {
        // Find the prompt and its associated server
        guard let prompt = availablePrompts.first(where: { $0.name == name }),
              let client = clients[prompt.serverId] else {
            throw MCPError.promptNotFound
        }
        
        // Convert arguments to MCP Value format
        var mcpArguments: [String: Value]? = nil
        if !arguments.isEmpty {
            mcpArguments = Dictionary(uniqueKeysWithValues: arguments.compactMap { (key, value) in
                if let stringValue = value as? String {
                    return (key, Value.string(stringValue))
                } else if let intValue = value as? Int {
                    return (key, Value.int(intValue))
                } else if let doubleValue = value as? Double {
                    return (key, Value.double(doubleValue))
                } else if let boolValue = value as? Bool {
                    return (key, Value.bool(boolValue))
                }
                return nil
            })
        }
        
        let (description, messages) = try await client.getPrompt(name: name, arguments: mcpArguments)
        
        // Combine description and messages into a single string
        var content = ""
        if let desc = description, !desc.isEmpty {
            content += "\(desc)\n\n"
        }
        
        let messageContent = messages.compactMap { message in
            // For now, just extract the raw content as string representation
            // The actual MCP SDK structure might be different from tool calling content
            return "\(message.content)"
        }.joined(separator: "\n\n")
        
        content += messageContent
        return content
    }
    
    // MARK: - Persistence
    
    private func loadServers() {
        AppLogger.shared.info("MCPManager", "Loading servers from MCPServerRegistry")
        let stored = serverRegistry.getStoredServers()
        if stored.isEmpty {
            AppLogger.shared.info("MCPManager", "No stored servers, loading defaults from registry")
            servers = serverRegistry.getStoredServers()
        } else {
            servers = stored
        }
        AppLogger.shared.info("MCPManager", "Loaded \(servers.count) server(s)")
        for (index, server) in servers.enumerated() {
            AppLogger.shared.debug("MCPManager", "Server \(index + 1): \(server.name) (enabled: \(server.isEnabled))")
            serverStatuses[server.id] = MCPServerStatus(serverId: server.id, status: .disconnected)
        }
    }
    
    private func saveServers() {
        serverRegistry.storeServers(servers)
    }
}

enum MCPError: LocalizedError {
    case serverNotConnected
    case toolNotFound
    case promptNotFound
    case invalidParameters
    
    var errorDescription: String? {
        switch self {
        case .serverNotConnected:
            return "MCP server is not connected"
        case .toolNotFound:
            return "Tool not found"
        case .promptNotFound:
            return "Prompt not found"
        case .invalidParameters:
            return "Invalid parameters"
        }
    }
}
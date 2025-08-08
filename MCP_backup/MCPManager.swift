import Foundation
// import MCP  // Temporarily commented out

@MainActor
final class MCPManager: ObservableObject {
    @Published private(set) var servers: [MCPServer] = []
    @Published private(set) var serverStatuses: [UUID: MCPServerStatus] = [:]
    @Published private(set) var availableTools: [MCPTool] = []
    @Published private(set) var availableResources: [MCPResource] = []
    @Published private(set) var isInitialized = false
    
    private var clients: [UUID: Any] = [:]  // Client temporarily changed to Any
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
        for server in servers.filter(\.isEnabled) {
            await connectToServer(server)
        }
        isInitialized = true
    }
    
    func connectToServer(_ server: MCPServer) async {
        updateServerStatus(server.id, status: .connecting)
        
        // TODO: Implement actual connection once MCP SDK transport API is clarified
        // For now, mark as disconnected to avoid crashes
        updateServerStatus(server.id, status: .disconnected, error: "Transport implementation pending")
        
        /*
        do {
            let client = Client(name: "Violet", version: "0.1.0")
            let transport = try transportFactory.createTransport(for: server)
            
            try await client.connect(transport: transport)
            clients[server.id] = client
            
            updateServerStatus(server.id, status: .connected)
            await discoverServerCapabilities(server)
            
        } catch {
            updateServerStatus(server.id, status: .error, error: error.localizedDescription)
        }
        */
    }
    
    func disconnectFromServer(_ server: MCPServer) {
        clients.removeValue(forKey: server.id)
        updateServerStatus(server.id, status: .disconnected)
        availableTools.removeAll { $0.serverId == server.id }
        availableResources.removeAll { $0.serverId == server.id }
    }
    
    private func discoverServerCapabilities(_ server: MCPServer) async {
        // TODO: Implement capabilities discovery once MCP SDK API is clarified
        /*
        guard let client = clients[server.id] else { return }
        
        do {
            // Discover tools
            let toolsResponse = try await client.listTools()
            let mcpTools = toolsResponse.tools.map { tool in
                MCPTool(
                    id: tool.name,
                    name: tool.name,
                    description: tool.description,
                    inputSchema: tool.inputSchema,
                    serverId: server.id
                )
            }
            availableTools.append(contentsOf: mcpTools)
            
            // Discover resources
            let resourcesResponse = try await client.listResources()
            let mcpResources = resourcesResponse.resources.map { resource in
                MCPResource(
                    id: resource.uri,
                    uri: resource.uri,
                    name: resource.name ?? resource.uri,
                    description: resource.description,
                    mimeType: resource.mimeType,
                    serverId: server.id
                )
            }
            availableResources.append(contentsOf: mcpResources)
            
        } catch {
            print("Failed to discover capabilities for server \(server.name): \(error)")
        }
        */
    }
    
    // MARK: - Tool Execution
    
    func callTool(_ tool: MCPTool, parameters: [String: Any]) async throws -> MCPToolResult {
        // TODO: Implement tool calling once MCP SDK API is clarified
        let callId = UUID()
        return MCPToolResult(
            callId: callId,
            isSuccess: false,
            error: "Tool calling implementation pending"
        )
        /*
        guard let client = clients[tool.serverId] else {
            throw MCPError.serverNotConnected
        }
        
        let callId = UUID()
        let call = MCPToolCall(id: callId, toolId: tool.id, parameters: parameters)
        
        do {
            let (content, isError) = try await client.callTool(name: tool.name, arguments: parameters)
            
            let contentString = content.compactMap { item in
                switch item {
                case .text(let text):
                    return text
                case .image(_, _, let alt):
                    return alt ?? "[Image]"
                case .resource(let resource):
                    return resource.text
                }
            }.joined(separator: "\n")
            
            return MCPToolResult(
                callId: callId,
                isSuccess: !isError,
                content: isError ? nil : contentString,
                error: isError ? contentString : nil
            )
            
        } catch {
            return MCPToolResult(
                callId: callId,
                isSuccess: false,
                error: error.localizedDescription
            )
        }
        */
    }
    
    // MARK: - Resource Access
    
    func readResource(_ resource: MCPResource) async throws -> MCPResourceContent {
        // TODO: Implement resource reading once MCP SDK API is clarified
        return MCPResourceContent(
            resourceId: resource.id,
            content: "Resource reading implementation pending",
            mimeType: resource.mimeType
        )
        /*
        guard let client = clients[resource.serverId] else {
            throw MCPError.serverNotConnected
        }
        
        let resourceResponse = try await client.readResource(uri: resource.uri)
        let content = resourceResponse.contents.compactMap { item in
            switch item {
            case .text(let text):
                return text
            case .resource(let resource):
                return resource.text
            default:
                return nil
            }
        }.joined(separator: "\n")
        
        return MCPResourceContent(
            resourceId: resource.id,
            content: content,
            mimeType: resource.mimeType
        )
        */
    }
    
    // MARK: - Persistence
    
    private func loadServers() {
        if let data = UserDefaults.standard.data(forKey: "MCPServers"),
           let decoded = try? JSONDecoder().decode([MCPServer].self, from: data) {
            servers = decoded
            for server in servers {
                serverStatuses[server.id] = MCPServerStatus(serverId: server.id, status: .disconnected)
            }
        }
    }
    
    private func saveServers() {
        if let encoded = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(encoded, forKey: "MCPServers")
        }
    }
}

enum MCPError: LocalizedError {
    case serverNotConnected
    case toolNotFound
    case invalidParameters
    
    var errorDescription: String? {
        switch self {
        case .serverNotConnected:
            return "MCP server is not connected"
        case .toolNotFound:
            return "Tool not found"
        case .invalidParameters:
            return "Invalid tool parameters"
        }
    }
}
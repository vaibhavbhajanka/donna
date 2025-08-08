import Foundation

struct MCPServer: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let url: URL
    let description: String?
    var isEnabled: Bool
    var authToken: String?
    
    init(
        id: UUID = UUID(),
        name: String,
        url: URL,
        description: String? = nil,
        isEnabled: Bool = true,
        authToken: String? = nil
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.description = description
        self.isEnabled = isEnabled
        self.authToken = authToken
    }
}

enum MCPConnectionStatus: String, CaseIterable {
    case disconnected
    case connecting
    case connected
    case error
    
    var displayName: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .error: return "Error"
        }
    }
}

struct MCPServerStatus: Identifiable, Equatable {
    let id: UUID
    let serverId: UUID
    let status: MCPConnectionStatus
    let lastError: String?
    let connectedAt: Date?
    
    init(serverId: UUID, status: MCPConnectionStatus, lastError: String? = nil, connectedAt: Date? = nil) {
        self.id = UUID()
        self.serverId = serverId
        self.status = status
        self.lastError = lastError
        self.connectedAt = connectedAt
    }
}
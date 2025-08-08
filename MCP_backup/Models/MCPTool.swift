import Foundation

struct MCPTool: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let description: String?
    let inputSchema: [String: Any]?
    let serverId: UUID
    
    static func == (lhs: MCPTool, rhs: MCPTool) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.description == rhs.description &&
        lhs.serverId == rhs.serverId
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, name, description, serverId
    }
    
    init(id: String, name: String, description: String? = nil, inputSchema: [String: Any]? = nil, serverId: UUID) {
        self.id = id
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.serverId = serverId
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        serverId = try container.decode(UUID.self, forKey: .serverId)
        inputSchema = nil
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(serverId, forKey: .serverId)
    }
}

struct MCPToolCall: Identifiable {
    let id: UUID
    let toolId: String
    let parameters: [String: Any]
    let timestamp: Date
    
    init(id: UUID = UUID(), toolId: String, parameters: [String: Any], timestamp: Date = Date()) {
        self.id = id
        self.toolId = toolId
        self.parameters = parameters
        self.timestamp = timestamp
    }
}

struct MCPToolResult: Identifiable {
    let id: UUID
    let callId: UUID
    let isSuccess: Bool
    let content: String?
    let error: String?
    let timestamp: Date
    
    init(id: UUID = UUID(), callId: UUID, isSuccess: Bool, content: String? = nil, error: String? = nil, timestamp: Date = Date()) {
        self.id = id
        self.callId = callId
        self.isSuccess = isSuccess
        self.content = content
        self.error = error
        self.timestamp = timestamp
    }
}
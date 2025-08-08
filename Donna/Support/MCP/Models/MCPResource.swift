import Foundation

struct MCPResource: Identifiable, Codable, Equatable {
    let id: String
    let uri: String
    let name: String
    let description: String?
    let mimeType: String?
    let serverId: UUID
    
    init(id: String, uri: String, name: String, description: String? = nil, mimeType: String? = nil, serverId: UUID) {
        self.id = id
        self.uri = uri
        self.name = name
        self.description = description
        self.mimeType = mimeType
        self.serverId = serverId
    }
}

struct MCPResourceContent: Identifiable {
    let id: UUID
    let resourceId: String
    let content: String
    let mimeType: String?
    let timestamp: Date
    
    init(id: UUID = UUID(), resourceId: String, content: String, mimeType: String? = nil, timestamp: Date = Date()) {
        self.id = id
        self.resourceId = resourceId
        self.content = content
        self.mimeType = mimeType
        self.timestamp = timestamp
    }
}
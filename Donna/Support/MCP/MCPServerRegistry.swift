import Foundation

final class MCPServerRegistry {
    private let storageKey = "MCPServerRegistry"
    private let authTokenPrefix = "MCPToken_"
    
    // MARK: - Server Configuration
    
    func getStoredServers() -> [MCPServer] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let servers = try? JSONDecoder().decode([MCPServer].self, from: data) else {
            return getDefaultServers()
        }
        return servers
    }
    
    func storeServers(_ servers: [MCPServer]) {
        if let data = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    private func getDefaultServers() -> [MCPServer] {
        return [
            MCPServer(
                name: "Apple MCP Server",
                url: URL(string: "stdio://bunx --no-cache apple-mcp@latest")!,
                description: "Access Apple apps: Messages, Notes, Contacts, Mail, Reminders, Calendar, Maps",
                isEnabled: true
            )
        ]
    }
    
    // MARK: - Authentication Token Management
    
    func storeAuthToken(for serverId: UUID, token: String) {
        let key = authTokenPrefix + serverId.uuidString
        if let data = token.data(using: .utf8) {
            let status = SecItemAdd([
                kSecClass: kSecClassGenericPassword,
                kSecAttrAccount: key,
                kSecValueData: data,
                kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ] as CFDictionary, nil)
            
            if status == errSecDuplicateItem {
                // Update existing item
                SecItemUpdate([
                    kSecClass: kSecClassGenericPassword,
                    kSecAttrAccount: key
                ] as CFDictionary, [
                    kSecValueData: data
                ] as CFDictionary)
            }
        }
    }
    
    func getAuthToken(for serverId: UUID) -> String? {
        let key = authTokenPrefix + serverId.uuidString
        var result: AnyObject?
        
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as CFDictionary, &result)
        
        if status == errSecSuccess,
           let data = result as? Data,
           let token = String(data: data, encoding: .utf8) {
            return token
        }
        
        return nil
    }
    
    func deleteAuthToken(for serverId: UUID) {
        let key = authTokenPrefix + serverId.uuidString
        SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key
        ] as CFDictionary)
    }
    
    // MARK: - Server Validation
    
    func validateServerConfiguration(_ server: MCPServer) -> [String] {
        var errors: [String] = []
        
        if server.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Server name is required")
        }
        
        if server.url.scheme != "http" && server.url.scheme != "https" && server.url.scheme != "stdio" {
            errors.append("Server URL must use http, https, or stdio scheme")
        }
        
        if server.url.scheme != "stdio" && server.url.host?.isEmpty != false {
            errors.append("Server URL must include a valid host (except for stdio URLs)")
        }
        
        return errors
    }
    
    func isServerNameUnique(_ name: String, excluding serverId: UUID? = nil) -> Bool {
        let servers = getStoredServers()
        return !servers.contains { server in
            server.name.lowercased() == name.lowercased() && 
            (serverId == nil || server.id != serverId)
        }
    }
    
    // MARK: - Server Capabilities Cache
    
    func getCachedCapabilities(for serverId: UUID) -> (tools: [MCPTool], resources: [MCPResource])? {
        let key = "MCPCapabilities_\(serverId.uuidString)"
        guard let data = UserDefaults.standard.data(forKey: key),
              let cached = try? JSONDecoder().decode(CachedCapabilities.self, from: data),
              Date().timeIntervalSince(cached.timestamp) < 3600 else { // 1 hour cache
            return nil
        }
        return (cached.tools, cached.resources)
    }
    
    func setCachedCapabilities(for serverId: UUID, tools: [MCPTool], resources: [MCPResource]) {
        let key = "MCPCapabilities_\(serverId.uuidString)"
        let cached = CachedCapabilities(tools: tools, resources: resources, timestamp: Date())
        if let data = try? JSONEncoder().encode(cached) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    
    func clearCachedCapabilities(for serverId: UUID) {
        let key = "MCPCapabilities_\(serverId.uuidString)"
        UserDefaults.standard.removeObject(forKey: key)
    }
}

private struct CachedCapabilities: Codable {
    let tools: [MCPTool]
    let resources: [MCPResource]
    let timestamp: Date
}
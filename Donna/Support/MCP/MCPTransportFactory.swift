import Foundation
import MCP
import System

final class MCPTransportFactory {
    
    enum TransportError: LocalizedError {
        case unsupportedScheme(String)
        case invalidURL(String)
        case authenticationRequired
        case invalidCommand(String)
        
        var errorDescription: String? {
            switch self {
            case .unsupportedScheme(let scheme):
                return "Unsupported URL scheme: \(scheme). Only http, https, and stdio are supported."
            case .invalidURL(let url):
                return "Invalid server URL: \(url)"
            case .authenticationRequired:
                return "Authentication token is required for this server"
            case .invalidCommand(let command):
                return "Invalid stdio command: \(command)"
            }
        }
    }
    
    func createTransport(for server: MCPServer) throws -> Transport {
        AppLogger.shared.debug("Transport", "Creating transport for \(server.name)")
        AppLogger.shared.debug("Transport", "URL: \(server.url)")
        
        guard let scheme = server.url.scheme?.lowercased() else {
            let error = TransportError.invalidURL(server.url.absoluteString)
            AppLogger.shared.error("Transport", "Invalid URL - no scheme found: \(error.localizedDescription)")
            throw error
        }
        
        AppLogger.shared.debug("Transport", "URL scheme: \(scheme)")
        
        switch scheme {
        case "http", "https":
            AppLogger.shared.debug("Transport", "Creating HTTP transport")
            return try createHTTPTransport(for: server)
        case "stdio":
            AppLogger.shared.debug("Transport", "Creating stdio transport")
            return try createStdioTransport(for: server)
        default:
            let error = TransportError.unsupportedScheme(scheme)
            AppLogger.shared.error("Transport", "Unsupported scheme: \(scheme)")
            throw error
        }
    }
    
    private func createHTTPTransport(for server: MCPServer) throws -> Transport {
        return HTTPClientTransport(
            endpoint: server.url,
            streaming: true  // Enable Server-Sent Events for real-time updates
        )
    }
    
    private func createStdioTransport(for server: MCPServer) throws -> Transport {
        AppLogger.shared.debug("Transport", "Setting up stdio transport")
        
        // Parse stdio:// URL to get command and arguments
        // Format: stdio://command arg1 arg2 arg3
        let urlString = server.url.absoluteString
        AppLogger.shared.debug("Transport", "Parsing URL: \(urlString)")
        
        guard urlString.hasPrefix("stdio://") else {
            let error = TransportError.invalidURL(urlString)
            AppLogger.shared.error("Transport", "Invalid stdio URL format: \(urlString)")
            throw error
        }
        
        let commandString = String(urlString.dropFirst(8)) // Remove "stdio://"
        AppLogger.shared.debug("Transport", "Command string: '\(commandString)'")
        
        // URL decode the command string to handle encoded spaces
        let decodedCommandString = commandString.removingPercentEncoding ?? commandString
        AppLogger.shared.debug("Transport", "Decoded command string: '\(decodedCommandString)'")
        
        let components = decodedCommandString.split(separator: " ").map(String.init)
        AppLogger.shared.debug("Transport", "Command components: \(components)")
        
        guard !components.isEmpty else {
            let error = TransportError.invalidCommand(commandString)
            AppLogger.shared.error("Transport", "Empty command for stdio URL")
            throw error
        }
        
        let command = components.first!
        let arguments = Array(components.dropFirst())
        AppLogger.shared.debug("Transport", "Command: '\(command)', Arguments: \(arguments)")
        
        // Create a Process to launch the MCP server
        let process = Process()
        
        // For bunx, we need to use the full path and set up proper environment
        if command == "bunx" {
            AppLogger.shared.debug("Transport", "Using bunx with full path")
            process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/bunx")
            process.arguments = arguments
        } else {
            AppLogger.shared.debug("Transport", "Using env to find command: \(command)")
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + arguments
        }
        
        // Set up environment variables
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        process.environment = env
        AppLogger.shared.debug("Transport", "Process executable: \(process.executableURL?.path ?? "nil")")
        AppLogger.shared.debug("Transport", "Process arguments: \(process.arguments ?? [])")
        
        // Set up pipes for communication
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        AppLogger.shared.debug("Transport", "Attempting to launch process…")
        
        // Launch the process
        do {
            try process.run()
            AppLogger.shared.info("Transport", "Process launched successfully, PID: \(process.processIdentifier)")
        } catch {
            AppLogger.shared.error("Transport", "Failed to launch process: \(error.localizedDescription)")
            throw error
        }
        
        // Create the StdioTransport with the process pipes
        AppLogger.shared.debug("Transport", "Creating StdioTransport with file descriptors")
        
        return StdioTransport(
            input: FileDescriptor(rawValue: outputPipe.fileHandleForReading.fileDescriptor),
            output: FileDescriptor(rawValue: inputPipe.fileHandleForWriting.fileDescriptor),
            logger: nil
        )
    }
    
    // MARK: - Transport Configuration
    
    func configureTransportOptions(for transport: Transport, server: MCPServer) {
        // Configure timeout and retry settings
        // TODO: Configure transport options once SDK API is clarified
    }
    
    // MARK: - Connection Testing
    
    func testConnection(to server: MCPServer) async throws -> Bool {
        let transport = try createTransport(for: server)
        let client = Client(name: "Donna-Test", version: "0.1.0")
        
        do {
            try await client.connect(transport: transport)
            // Try to list tools to verify the connection works
            let (_, _) = try await client.listTools()
            return true
        } catch {
            throw error
        }
    }
    
    // MARK: - Health Check
    
    func performHealthCheck(for server: MCPServer) async -> HealthCheckResult {
        do {
            let isHealthy = try await testConnection(to: server)
            return HealthCheckResult(
                serverId: server.id,
                isHealthy: isHealthy,
                responseTime: 0, // Would measure actual response time
                error: nil,
                timestamp: Date()
            )
        } catch {
            return HealthCheckResult(
                serverId: server.id,
                isHealthy: false,
                responseTime: nil,
                error: error.localizedDescription,
                timestamp: Date()
            )
        }
    }
}

struct HealthCheckResult {
    let serverId: UUID
    let isHealthy: Bool
    let responseTime: TimeInterval?
    let error: String?
    let timestamp: Date
}
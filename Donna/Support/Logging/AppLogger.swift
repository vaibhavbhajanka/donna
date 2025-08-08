import Foundation
import OSLog
import Combine

enum LogLevel: String {
    case debug
    case info
    case warning
    case error
}

struct LogEvent: Identifiable {
    let id: UUID = UUID()
    let timestamp: Date
    let level: LogLevel
    let category: String
    let message: String
}

final class AppLogger: ObservableObject {
    static let shared = AppLogger()

    private let subsystem: String
    private let loggingQueue = DispatchQueue(label: "Donna.Logger.Queue", qos: .utility)

    @Published private(set) var events: [LogEvent] = []
    private let maxEvents: Int = 500

    private var fileHandle: FileHandle?

    private init() {
        self.subsystem = Bundle.main.bundleIdentifier ?? "Donna"
    }

    // MARK: - Public API
    func debug(_ category: String, _ message: String) { log(.debug, category, message) }
    func info(_ category: String, _ message: String)  { log(.info, category, message) }
    func warn(_ category: String, _ message: String)  { log(.warning, category, message) }
    func error(_ category: String, _ message: String) { log(.error, category, message) }

    func enableFileLogging() {
        loggingQueue.async {
            let fileManager = FileManager.default
            guard let baseURL = try? fileManager.url(for: .applicationSupportDirectory,
                                                     in: .userDomainMask,
                                                     appropriateFor: nil,
                                                     create: true) else { return }
            let dirURL = baseURL.appendingPathComponent("Donna", isDirectory: true)
            try? fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true)
            let fileURL = dirURL.appendingPathComponent("donna.log")
            if !fileManager.fileExists(atPath: fileURL.path) {
                fileManager.createFile(atPath: fileURL.path, contents: nil)
            }
            do {
                self.fileHandle = try FileHandle(forWritingTo: fileURL)
                try self.fileHandle?.seekToEnd()
            } catch {
                self.fileHandle = nil
            }
        }
    }

    // MARK: - Core
    private func log(_ level: LogLevel, _ category: String, _ message: String) {
        loggingQueue.async {
            let logger = Logger(subsystem: self.subsystem, category: category)
            switch level {
            case .debug:
                logger.debug("\(message, privacy: .public)")
            case .info:
                logger.info("\(message, privacy: .public)")
            case .warning:
                logger.warning("\(message, privacy: .public)")
            case .error:
                logger.error("\(message, privacy: .public)")
            }

            let event = LogEvent(timestamp: Date(), level: level, category: category, message: message)
            DispatchQueue.main.async {
                self.events.append(event)
                if self.events.count > self.maxEvents {
                    self.events.removeFirst(self.events.count - self.maxEvents)
                }
            }

            if let handle = self.fileHandle {
                let timestamp = self.timestampString(from: event.timestamp)
                let levelString = level.rawValue.uppercased()
                let line = "[\(timestamp)] [\(levelString)] [\(category)] \(message)\n"
                if let data = line.data(using: .utf8) {
                    try? handle.write(contentsOf: data)
                }
            }
        }
    }

    private func timestampString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}



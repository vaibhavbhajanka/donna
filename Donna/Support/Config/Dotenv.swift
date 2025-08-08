import Foundation

/// Minimal .env loader for macOS apps.
/// Search order:
/// 1) ~/Library/Application Support/Donna/.env
/// 2) ~/.donna.env
/// Values are cached after first read.
enum Dotenv {
    private static var cached: [String: String]? = nil

    static func get(_ key: String) -> String? {
        if cached == nil {
            cached = loadEnv()
        }
        return cached?[key]
    }

    private static func loadEnv() -> [String: String] {
        var locations: [URL] = []
        let fileManager = FileManager.default

        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let path = appSupport.appendingPathComponent("Donna/.env", isDirectory: false)
            locations.append(path)
        }
        let home = fileManager.homeDirectoryForCurrentUser
        let homeDotfile = home.appendingPathComponent(".donna.env", isDirectory: false)
        locations.append(homeDotfile)

        for url in locations {
            if fileManager.fileExists(atPath: url.path), let dict = parseEnvFile(at: url) {
                return dict
            }
        }
        return [:]
    }

    private static func parseEnvFile(at url: URL) -> [String: String]? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var result: [String: String] = [:]
        content
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .forEach { lineSub in
                var line = String(lineSub)
                // Trim whitespace
                line = line.trimmingCharacters(in: .whitespacesAndNewlines)
                // Skip comments and empty
                if line.isEmpty || line.hasPrefix("#") { return }
                // Split on first '='
                guard let eq = line.firstIndex(of: "=") else { return }
                let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
                var value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                // Remove optional surrounding quotes
                if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                    value = String(value.dropFirst().dropLast())
                }
                if !key.isEmpty { result[key] = value }
            }
        return result
    }
}

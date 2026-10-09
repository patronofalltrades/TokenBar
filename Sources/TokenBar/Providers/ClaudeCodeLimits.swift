import Foundation

/// Reads the Claude limits file that the status line bridge writes (TRD Section 5.1).
/// The file holds only the two limit windows and the write time.
enum ClaudeCodeLimits {
    static let defaultFile = URL.applicationSupportDirectory.appending(path: "TokenBar/claude-limits.json")

    /// The file format. The bridge also decodes `rate_limits` from the status line input with these types.
    struct Stored: Codable {
        var five_hour: Window?
        var seven_day: Window?
        var observed_at: Double?  // epoch seconds. Absent in the status line input.
    }

    struct Window: Codable {
        let used_percentage: Double
        let resets_at: Double  // epoch seconds
    }

    /// Returns no windows if the file does not exist: the user did not set up the bridge.
    /// Throws if the file exists but TokenBar cannot read it (TRD 5.1: only an unreadable file is an error).
    static func read(from file: URL = defaultFile) throws -> [LimitWindow] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        let stored = try JSONDecoder().decode(Stored.self, from: Data(contentsOf: file))
        let observedAt = Date(timeIntervalSince1970: stored.observed_at ?? 0)
        return [("5-hour", stored.five_hour), ("weekly", stored.seven_day)].compactMap { name, window in
            window.map {
                LimitWindow(name: name, usedPercent: $0.used_percentage,
                            resetsAt: Date(timeIntervalSince1970: $0.resets_at), observedAt: observedAt)
            }
        }
    }
}

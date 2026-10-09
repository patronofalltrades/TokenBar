import Foundation

/// One-click setup of the Claude limit bridge (TRD Section 5.1, D39).
/// Connect sets TokenBar as the Claude Code status line. It keeps a backup of the settings file
/// and saves the old status line, so that the bridge can run it after TokenBar.
enum ClaudeConnect {
    static let defaultSettingsFile = URL.homeDirectory.appending(path: ".claude/settings.json")
    static let defaultPreviousFile = URL.applicationSupportDirectory.appending(path: "TokenBar/statusline-previous.json")

    /// The status line command for this copy of TokenBar. Single quotes keep a path with spaces as one word.
    static var command: String {
        let path = Bundle.main.executablePath ?? CommandLine.arguments[0]
        return "'" + path.replacingOccurrences(of: "'", with: #"'\''"#) + "' --statusline"
    }

    enum Status: Equatable {
        case notConnected
        case connectedWaiting
        case connected(updatedAt: Date)
    }

    struct InvalidSettings: LocalizedError {
        var errorDescription: String? {
            "Your Claude Code settings file (~/.claude/settings.json) is not a valid JSON object. TokenBar did not change it."
        }
    }

    static func isTokenBar(_ statusLine: Any?) -> Bool {
        guard let command = (statusLine as? [String: Any])?["command"] as? String else { return false }
        return command.contains("--statusline") && command.contains("TokenBar")
    }

    /// Sets TokenBar as the status line. Keeps all other keys and the old `padding`.
    /// Throws, and changes nothing, if the settings file is not a JSON object.
    static func connect(settingsFile: URL = defaultSettingsFile, previousFile: URL = defaultPreviousFile,
                        command: String = ClaudeConnect.command) throws {
        let settingsFile = settingsFile.resolvingSymlinksInPath()  // An atomic write must not replace a dotfiles link.
        var settings = try read(settingsFile)
        let old = settings["statusLine"]
        var new: [String: Any] = ["type": "command", "command": command]
        if let padding = (old as? [String: Any])?["padding"] { new["padding"] = padding }
        if let old = old as? NSDictionary, old.isEqual(to: new) { return }

        let backup = settingsFile.appendingPathExtension("tokenbar-backup")
        let fm = FileManager.default
        if fm.fileExists(atPath: settingsFile.path), !fm.fileExists(atPath: backup.path) {
            try fm.copyItem(at: settingsFile, to: backup)
        }
        // A TokenBar status line from an earlier connect is not the user's. Keep the saved one.
        if let old, !isTokenBar(old) {
            try fm.createDirectory(at: previousFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: old, options: .fragmentsAllowed).write(to: previousFile, options: .atomic)
        }
        settings["statusLine"] = new
        try write(settings, to: settingsFile)
    }

    /// Puts back the saved status line, or removes the key if no status line was saved.
    /// Does nothing if the current status line is not TokenBar's.
    static func disconnect(settingsFile: URL = defaultSettingsFile, previousFile: URL = defaultPreviousFile) throws {
        let settingsFile = settingsFile.resolvingSymlinksInPath()
        var settings = try read(settingsFile)
        guard isTokenBar(settings["statusLine"]) else { return }
        settings["statusLine"] = (try? Data(contentsOf: previousFile))
            .flatMap { try? JSONSerialization.jsonObject(with: $0, options: .fragmentsAllowed) }
        try write(settings, to: settingsFile)
        try? FileManager.default.removeItem(at: previousFile)
    }

    static func status(settingsFile: URL = defaultSettingsFile, limitsFile: URL = ClaudeCodeLimits.defaultFile) -> Status {
        guard let settings = try? read(settingsFile.resolvingSymlinksInPath()), isTokenBar(settings["statusLine"]) else {
            return .notConnected
        }
        guard let stored = try? JSONDecoder().decode(ClaudeCodeLimits.Stored.self, from: Data(contentsOf: limitsFile)),
              let observedAt = stored.observed_at else { return .connectedWaiting }
        return .connected(updatedAt: Date(timeIntervalSince1970: observedAt))
    }

    /// A missing file is an empty object.
    private static func read(_ file: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [:] }
        let data = try Data(contentsOf: file)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw InvalidSettings() }
        return object
    }

    private static func write(_ settings: [String: Any], to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            .write(to: file, options: .atomic)
    }
}

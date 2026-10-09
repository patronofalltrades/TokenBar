import Foundation
import Testing
@testable import TokenBar

/// Temp directories only. These tests never read or write the real ~/.claude/settings.json.
@Suite struct ClaudeConnectTests {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("connect-\(UUID().uuidString)")
    var settings: URL { dir.appending(path: ".claude/settings.json") }
    var backup: URL { dir.appending(path: ".claude/settings.json.tokenbar-backup") }
    var previous: URL { dir.appending(path: "TokenBar/statusline-previous.json") }
    var limits: URL { dir.appending(path: "TokenBar/claude-limits.json") }
    let command = "'/Users/me/My Apps/TokenBar.app/Contents/MacOS/TokenBar' --statusline"

    private func write(_ text: String, to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }

    private func json(_ file: URL) throws -> NSDictionary {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? NSDictionary)
    }

    private func connect() throws {
        try ClaudeConnect.connect(settingsFile: settings, previousFile: previous, command: command)
    }

    private func disconnect() throws {
        try ClaudeConnect.disconnect(settingsFile: settings, previousFile: previous)
    }

    private var tokenBarLine: NSDictionary { ["type": "command", "command": command] }

    @Test func connectOnMissingFile() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try connect()
        #expect(try json(settings) == ["statusLine": tokenBarLine])
        #expect(!FileManager.default.fileExists(atPath: backup.path))
        #expect(!FileManager.default.fileExists(atPath: previous.path))
        let text = try String(contentsOf: settings, encoding: .utf8)
        #expect(text.contains("/Users/me/My Apps/TokenBar.app"))  // No escaped slashes.
        #expect(text.contains("\n"))  // Pretty-printed.
    }

    @Test func connectOnEmptyObjectKeepsBackup() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try write("{}", to: settings)
        try connect()
        #expect(try json(settings) == ["statusLine": tokenBarLine])
        #expect(try String(contentsOf: backup, encoding: .utf8) == "{}")
    }

    @Test func connectKeepsOtherKeys() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try write(#"{"model":"opus","permissions":{"allow":["Bash(ls)"]},"disableAllHooks":false}"#, to: settings)
        try connect()
        let result = try json(settings)
        #expect(result["model"] as? String == "opus")
        #expect(result["permissions"] as? NSDictionary == ["allow": ["Bash(ls)"]])
        #expect(result["disableAllHooks"] as? Bool == false)
        #expect(result["statusLine"] as? NSDictionary == tokenBarLine)
    }

    @Test func connectSavesCustomStatusLineAndKeepsPadding() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = #"{"type":"command","command":"~/bin/my-line.sh","padding":2}"#
        try write(#"{"statusLine":\#(old)}"#, to: settings)
        try connect()
        #expect(try json(previous) == ["type": "command", "command": "~/bin/my-line.sh", "padding": 2])
        #expect(try json(settings)["statusLine"] as? NSDictionary == ["type": "command", "command": command, "padding": 2])
    }

    @Test(arguments: ["not json", "[1,2]", "\"text\""])
    func invalidSettingsThrowAndChangeNothing(text: String) throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try write(text, to: settings)
        #expect(throws: ClaudeConnect.InvalidSettings.self) { try connect() }
        #expect(try String(contentsOf: settings, encoding: .utf8) == text)
        #expect(!FileManager.default.fileExists(atPath: backup.path))
        #expect(!FileManager.default.fileExists(atPath: previous.path))
    }

    @Test func connectTwiceChangesNothing() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try write(#"{"statusLine":{"type":"command","command":"echo old"}}"#, to: settings)
        try connect()
        let first = try Data(contentsOf: settings)
        try connect()
        #expect(try Data(contentsOf: settings) == first)
        #expect(try json(previous) == ["type": "command", "command": "echo old"])
    }

    /// A new app path changes the command. The saved status line and the first backup stay.
    @Test func reconnectWithNewPathKeepsPreviousAndBackup() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try write(#"{"statusLine":{"type":"command","command":"echo old"}}"#, to: settings)
        try connect()
        try ClaudeConnect.connect(settingsFile: settings, previousFile: previous, command: "/tmp/TokenBar --statusline")
        #expect(try json(previous) == ["type": "command", "command": "echo old"])
        #expect(try json(backup) == ["statusLine": ["type": "command", "command": "echo old"]])
        #expect(try json(settings)["statusLine"] as? NSDictionary == ["type": "command", "command": "/tmp/TokenBar --statusline"])
    }

    @Test func disconnectRestoresExactOldObject() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let old: NSDictionary = ["type": "command", "command": "~/bin/my-line.sh", "padding": 0, "refreshInterval": 5]
        try write(#"{"model":"opus","statusLine":{"type":"command","command":"~/bin/my-line.sh","padding":0,"refreshInterval":5}}"#, to: settings)
        try connect()
        try disconnect()
        #expect(try json(settings) == ["model": "opus", "statusLine": old])
        #expect(!FileManager.default.fileExists(atPath: previous.path))
    }

    @Test func disconnectRemovesKeyWhenNothingSaved() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try write(#"{"model":"opus"}"#, to: settings)
        try connect()
        try disconnect()
        #expect(try json(settings) == ["model": "opus"])
    }

    @Test func disconnectLeavesOtherStatusLine() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let text = #"{"statusLine":{"type":"command","command":"echo mine"}}"#
        try write(text, to: settings)
        try disconnect()
        #expect(try String(contentsOf: settings, encoding: .utf8) == text)
    }

    @Test func statusValues() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let status = { ClaudeConnect.status(settingsFile: settings, limitsFile: limits) }
        #expect(status() == .notConnected)
        try write(#"{"statusLine":{"type":"command","command":"echo mine"}}"#, to: settings)
        #expect(status() == .notConnected)
        try connect()
        #expect(status() == .connectedWaiting)
        try write(#"{"five_hour":{"used_percentage":10,"resets_at":1791001000},"observed_at":1791000000}"#, to: limits)
        #expect(status() == .connected(updatedAt: Date(timeIntervalSince1970: 1_791_000_000)))
    }

    @Test func commandQuotesPath() {
        #expect(ClaudeConnect.command.hasPrefix("'"))
        #expect(ClaudeConnect.command.hasSuffix("' --statusline"))
    }

    @Test func isTokenBar() {
        #expect(ClaudeConnect.isTokenBar(["command": "~/Applications/TokenBar.app/Contents/MacOS/TokenBar --statusline"]))
        #expect(!ClaudeConnect.isTokenBar(["command": "~/bin/line.sh --statusline"]))
        #expect(!ClaudeConnect.isTokenBar(["command": "TokenBar"]))
        #expect(!ClaudeConnect.isTokenBar(nil))
    }
}

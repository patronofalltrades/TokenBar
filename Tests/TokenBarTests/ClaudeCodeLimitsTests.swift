import Foundation
import Testing
@testable import TokenBar

@Suite struct ClaudeCodeLimitsTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("limits-\(UUID().uuidString)")
    var file: URL { folder.appendingPathComponent("claude-limits.json") }

    private func write(_ text: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }

    @Test func mapsWindows() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try write(#"{"five_hour":{"used_percentage":62.4,"resets_at":1791001000},"seven_day":{"used_percentage":23.5,"resets_at":1791500000},"observed_at":1791000000}"#)
        let limits = try ClaudeCodeLimits.read(from: file)
        #expect(limits.map(\.name) == ["5-hour", "weekly"])
        #expect(limits.map(\.usedPercent) == [62.4, 23.5])
        #expect(limits.map(\.resetsAt) == [Date(timeIntervalSince1970: 1_791_001_000), Date(timeIntervalSince1970: 1_791_500_000)])
        #expect(limits.allSatisfy { $0.observedAt == Date(timeIntervalSince1970: 1_791_000_000) })
    }

    @Test func oneWindowOnly() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try write(#"{"seven_day":{"used_percentage":10,"resets_at":1791500000},"observed_at":1791000000}"#)
        #expect(try ClaudeCodeLimits.read(from: file).map(\.name) == ["weekly"])
    }

    @Test func missingFileGivesNoLimits() throws {
        #expect(try ClaudeCodeLimits.read(from: file).isEmpty)
    }

    @Test func unreadableFileThrows() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try write("not json")
        #expect(throws: (any Error).self) { try ClaudeCodeLimits.read(from: file) }
    }

    /// The bridge output goes into the Claude Code snapshot.
    @Test func providerIncludesLimits() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let root = folder.appendingPathComponent("projects")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let input = Data(#"{"session_name":"SECRET-MARKER","rate_limits":{"five_hour":{"used_percentage":40,"resets_at":1791001000}}}"#.utf8)
        let now = Date(timeIntervalSince1970: 1_791_000_000)
        _ = StatuslineBridge.run(input: input, file: file, now: now)

        let snapshot = try await ClaudeCodeProvider(roots: [root], limitsFile: file).fetch(now: now)
        #expect(snapshot.limits.map(\.name) == ["5-hour"])
        #expect(snapshot.limits.first?.usedPercent == 40)
        #expect(snapshot.limits.first?.observedAt == now)
    }
}

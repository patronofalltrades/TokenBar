import Foundation
import Testing
@testable import TokenBar

/// Synthetic status line input only. The shape follows https://code.claude.com/docs/en/statusline.
@Suite struct StatuslineBridgeTests {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("bridge-\(UUID().uuidString)/claude-limits.json")
    let now = Date(timeIntervalSince1970: 1_791_000_000)

    private func input(rateLimits: String?) -> Data {
        let limits = rateLimits.map { #","rate_limits":\#($0)"# } ?? ""
        return Data(#"""
        {"session_id":"abc","session_name":"SECRET-MARKER title","transcript_path":"/Users/me/SECRET-MARKER/t.jsonl","cwd":"/Users/me/SECRET-MARKER","model":{"id":"claude-opus-5-5","display_name":"Opus"},"workspace":{"current_dir":"/Users/me/SECRET-MARKER","project_dir":"/Users/me/SECRET-MARKER"},"cost":{"total_cost_usd":1.5}\#(limits)}
        """#.utf8)
    }

    private let both = #"{"five_hour":{"used_percentage":62.4,"resets_at":1791001000},"seven_day":{"used_percentage":23.5,"resets_at":1791500000},"spend_limit":{"used_percentage":5,"resets_at":1791600000,"used_usd":"SECRET-MARKER"}}"#

    private func stored() throws -> ClaudeCodeLimits.Stored {
        try JSONDecoder().decode(ClaudeCodeLimits.Stored.self, from: Data(contentsOf: file))
    }

    @Test func writesOnlyRateLimits() throws {
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        #expect(StatuslineBridge.run(input: input(rateLimits: both), file: file, now: now) == "TokenBar · 5h 62% · wk 24%")

        let bytes = try Data(contentsOf: file)
        #expect(bytes.range(of: Data("SECRET-MARKER".utf8)) == nil)
        let keys = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any]).keys
        #expect(Set(keys) == ["five_hour", "seven_day", "observed_at"])
        let limits = try stored()
        #expect(limits.five_hour?.used_percentage == 62.4)
        #expect(limits.seven_day?.resets_at == 1_791_500_000)
        #expect(limits.observed_at == now.timeIntervalSince1970)
    }

    /// No Pro or Max plan, or no API response yet: keep the old file, write nothing new.
    @Test func noRateLimitsWritesNothing() throws {
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        #expect(StatuslineBridge.run(input: input(rateLimits: nil), file: file, now: now) == "TokenBar")
        #expect(!FileManager.default.fileExists(atPath: file.path))

        _ = StatuslineBridge.run(input: input(rateLimits: both), file: file, now: now)
        _ = StatuslineBridge.run(input: input(rateLimits: "{}"), file: file, now: now.addingTimeInterval(60))
        #expect(try stored().observed_at == now.timeIntervalSince1970)
    }

    @Test func malformedInputIsSafe() {
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        for bad in ["", "not json", "[1,2]", #"{"rate_limits":{"five_hour":{"used_percentage":"x"}}}"#] {
            #expect(StatuslineBridge.run(input: Data(bad.utf8), file: file, now: now) == "TokenBar")
        }
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    /// Claude Code drops a window after its reset time. The bridge keeps the old window, so the app can show it as reset.
    @Test func keepsDroppedWindow() throws {
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        _ = StatuslineBridge.run(input: input(rateLimits: both), file: file, now: now)
        let line = StatuslineBridge.run(
            input: input(rateLimits: #"{"seven_day":{"used_percentage":30,"resets_at":1791500000}}"#),
            file: file, now: now.addingTimeInterval(3600))
        #expect(line == "TokenBar · 5h 62% · wk 30%")
        let limits = try stored()
        #expect(limits.five_hour?.resets_at == 1_791_001_000)
        #expect(limits.seven_day?.used_percentage == 30)
        #expect(limits.observed_at == now.timeIntervalSince1970 + 3600)
    }
}

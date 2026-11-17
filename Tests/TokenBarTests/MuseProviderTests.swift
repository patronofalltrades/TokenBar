import Foundation
import Testing
@testable import TokenBar

/// Synthetic fixtures only (TRD Section 12). No line comes from a real session file.
@Suite struct MuseProviderTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("muse-\(UUID().uuidString)/sessions")
    let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded())

    private func completed(input: Int = 1200, output: Int = 90, cached: Int = 800, write: Int = 0,
                           model: String = "meta/muse-spark-1.3", kind: String = "model_completed", ago: TimeInterval = 300) -> String {
        let micros = Int((now.timeIntervalSince1970 - ago) * 1_000_000)
        return #"{"recorded_at": \#(micros), "record_type": "event", "payload_type": "runtime.session", "sequence": 4, "id": "rec-4", "#
            + #""stream": {"kind": "session", "id": "s1"}, "payload": {"kind": "run", "run_id": "run-a", "event": {"kind": "\#(kind)", "#
            + #""model": "\#(model)", "duration_ms": 900, "finish_reason": "tool_calls", "text": "SECRET-MARKER", "#
            + #""usage": {"input_tokens": \#(input), "output_tokens": \#(output), "cached_tokens": \#(cached), "#
            + #""cache_read_tokens": \#(cached), "cache_write_tokens": \#(write), "reasoning_tokens": 40}}}}"#
    }

    private let prompt = #"{"recorded_at": 1, "payload_type": "runtime.session", "payload": {"kind": "message", "text": "tell me about model_completed"}}"#

    @discardableResult
    private func write(_ lines: [String], session: String = "2026/11/17/s1") throws -> URL {
        let dir = root.appendingPathComponent(session)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("session.jsonl")
        try Data(lines.map { $0 + "\n" }.joined().utf8).write(to: url)
        return url
    }

    private func records() async throws -> [UsageRecord] {
        try await MuseProvider(root: root).fetch(now: now).records
    }

    @Test func mapsTokens() async throws {
        // input includes the cache read. output includes the reasoning. The "meta/" prefix goes.
        try write([prompt, completed(write: 7)])
        let records = try await records()
        #expect(records.count == 1)
        #expect(records[0].provider == .muse && records[0].model == "muse-spark-1.3")
        #expect(records[0].timestamp == now.addingTimeInterval(-300))
        #expect(records[0].tokens == TokenCounts(input: 400, output: 90, cacheRead: 800, cacheWrite5m: 7))
    }

    @Test func countsOnlyModelCompletedEvents() async throws {
        // The other usage events repeat the same tokens. A replayed line counts one time.
        try write([completed(kind: "goal_usage_attribution"), completed(kind: "workflow_child_lifecycle"),
                   completed(), completed(), completed(ago: 200)])
        #expect(try await records().count == 2)
    }

    @Test func readsSubagentFilesAndSkipsDerivedViews() async throws {
        try write([completed()])
        try write([completed(model: "muse-spark-1.3-contributor", ago: 100)], session: "2026/11/17/s1/subagent/c1")
        try write([completed(ago: 50)], session: ".msp-view-v1/s1")
        let models = try await records().map(\.model).sorted()
        #expect(models == ["muse-spark-1.3", "muse-spark-1.3-contributor"])
    }

    @Test func dropsRecordsOutsideTheWindow() async throws {
        try write([completed(ago: 36 * 24 * 3600), completed()])
        #expect(try await records().count == 1)
    }

    @Test func missingRootIsNotInstalled() async {
        await #expect(throws: CocoaError.self) { try await records() }
    }

    @Test func shippedPricesCoverMuseModels() throws {
        let table = try PriceTable.shipped()
        #expect(table.price(for: "muse-spark-1.3")?.prices.output == Decimal(string: "4.25"))
        #expect(table.price(for: "muse-spark-1.3-contributor")?.prices.output == Decimal(string: "0.2"))
        #expect(table.price(for: "muse-spark-9") == nil)
    }
}

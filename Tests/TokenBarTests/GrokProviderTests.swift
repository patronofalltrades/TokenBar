import Foundation
import Testing
@testable import TokenBar

/// Synthetic fixtures only (TRD Section 12). No line comes from a real log.
@Suite struct GrokProviderTests {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("grok-\(UUID().uuidString)")
    let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded())

    private func iso(_ secondsAgo: TimeInterval) -> String {
        Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(now.addingTimeInterval(-secondsAgo))
    }

    private func inference(sid: String = "s-1", prompt: Int = 1000, cached: Int = 400, completion: Int = 80,
                           ts: String? = nil, ago: TimeInterval = 300) -> String {
        #"{"ts":\#(ts ?? "\"\(iso(ago))\""),"src":"shell","pid":42,"lvl":"info","msg":"shell.turn.inference_done","#
            + #""ctx":{"prompt_tokens":\#(prompt),"cached_prompt_tokens":\#(cached),"completion_tokens":\#(completion),"#
            + #""reasoning_tokens":20,"model_elapsed_ms":15,"attempts":1},"ver":"0","sid":"\#(sid)"}"#
    }

    private func writeLog(_ lines: [String]) throws {
        let dir = home.appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(lines.map { $0 + "\n" }.joined().utf8).write(to: dir.appendingPathComponent("unified.jsonl"))
    }

    private func writeSummary(_ json: String, sid: String = "s-1") throws {
        let dir = home.appendingPathComponent("sessions/%2FUsers%2Fme%2Fproject/\(sid)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: dir.appendingPathComponent("summary.json"))
    }

    @Test func mapsTokensAndReadsTheModelFromTheSummary() async throws {
        // prompt includes cached. completion includes reasoning.
        try writeLog([#"{"ts":"\#(iso(400))","pid":42,"msg":"process started"}"#,
                      #"{"ts":"\#(iso(350))","msg":"user typed shell.turn.inference_done"}"#, inference()])
        try writeSummary(#"{"info":{"id":"s-1","cwd":"SECRET-MARKER"},"current_model_id":"grok-build-0.1"}"#)
        let records = try await GrokProvider(home: home).fetch(now: now).records
        #expect(records.count == 1)
        #expect(records[0].provider == .grok && records[0].model == "grok-build-0.1")
        #expect(records[0].timestamp == now.addingTimeInterval(-300))
        #expect(records[0].tokens == TokenCounts(input: 600, output: 80, cacheRead: 400))
    }

    @Test func modelFallbacks() async throws {
        try writeLog([inference(sid: "a", ago: 10), inference(sid: "b", ago: 20), inference(sid: "../a", ago: 30)])
        try writeSummary(#"{"info":{"current_model_id":"grok-4.5"}}"#, sid: "a")
        let records = try await GrokProvider(home: home).fetch(now: now).records.sorted { $0.timestamp > $1.timestamp }
        // No summary, or an ID that is not a safe path component: no model.
        #expect(records.map(\.model) == ["grok-4.5", "unknown", "unknown"])
    }

    /// D61: a corrupt count must not crash the app.
    @Test func corruptCountsAreClamped() async throws {
        try writeLog([inference(prompt: Int.max, cached: Int.max, completion: Int.min)])
        let max = TokenCounts.maximumCount
        let records = try await GrokProvider(home: home).fetch(now: now).records
        #expect(records.map(\.tokens) == [TokenCounts(input: 0, output: 0, cacheRead: max)])
    }

    /// D61: a session without a summary cost one file read in each project folder at each refresh.
    @Test func missingSummaryIsNotSearchedAgainForFiveMinutes() async throws {
        try writeLog([inference()])
        let provider = GrokProvider(home: home)
        #expect(try await provider.fetch(now: now).records.first?.model == "unknown")
        try writeSummary(#"{"current_model_id":"grok-4.5"}"#)
        #expect(try await provider.fetch(now: now.addingTimeInterval(60)).records.first?.model == "unknown")
        #expect(try await provider.fetch(now: now.addingTimeInterval(301)).records.first?.model == "grok-4.5")
    }

    @Test func repeatedRowCountsOneTime() async throws {
        try writeLog([inference(), inference(), inference(ago: 200), inference(ago: 36 * 24 * 3600)])
        #expect(try await GrokProvider(home: home).fetch(now: now).records.count == 2)
    }

    @Test func numberTimestampIsSecondsOrMilliseconds() async throws {
        let seconds = Int(now.timeIntervalSince1970) - 60
        try writeLog([inference(ts: "\(seconds)"), inference(ts: "\(seconds * 1000 + 30_000)")])
        let times = try await GrokProvider(home: home).fetch(now: now).records.map(\.timestamp).sorted()
        #expect(times == [now.addingTimeInterval(-60), now.addingTimeInterval(-30)])
    }

    @Test func keepsRowsWhenTheLogStartsAgain() async throws {
        let provider = GrokProvider(home: home)
        try writeLog([inference(ago: 300), inference(ago: 200)])
        #expect(try await provider.fetch(now: now).records.count == 2)
        try writeLog([inference(ago: 100)])
        #expect(try await provider.fetch(now: now).records.count == 3)
    }

    @Test func missingHomeIsNotInstalled() async {
        await #expect(throws: CocoaError.self) { try await GrokProvider(home: home).fetch(now: now) }
    }

    @Test func shippedPricesCoverGrokModels() throws {
        let table = try PriceTable.shipped()
        let build = try #require(table.price(for: "grok-build-0.1"))
        #expect(build.usd(TokenCounts(input: 100_000)) == Decimal(string: "0.1"))
        // A prompt of 200,000 tokens or more has the higher price for all its tokens.
        #expect(build.usd(TokenCounts(input: 200_000)) == Decimal(string: "0.4"))
        #expect(table.price(for: "grok-4.5-build") == nil)
    }
}

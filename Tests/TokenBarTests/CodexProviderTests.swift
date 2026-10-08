import Foundation
import Testing
@testable import TokenBar

/// Synthetic fixtures only (TRD Section 12). No line comes from a real log.
@Suite struct CodexProviderTests {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("codex-\(UUID().uuidString)")
    let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded())  // whole seconds, like the log timestamps

    private func iso(_ secondsAgo: TimeInterval) -> String {
        Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(now.addingTimeInterval(-secondsAgo))
    }

    private func turnContext(_ model: String, ago: TimeInterval = 600) -> String {
        #"{"timestamp":"\#(iso(ago))","ordinal":1,"type":"turn_context","payload":{"model":"\#(model)","cwd":"/tmp","collaboration_mode":{"settings":{"developer_instructions":"SECRET-MARKER"}}}}"#
    }

    private func usageRecord(_ id: String, input: Int, cached: Int, output: Int, reasoning: Int = 0, ago: TimeInterval = 300) -> String {
        #"{"timestamp":"\#(iso(ago))","ordinal":2,"type":"token_usage_record","payload":{"response_id":"\#(id)","usage":{"input_tokens":\#(input),"cached_input_tokens":\#(cached),"cache_write_input_tokens":0,"output_tokens":\#(output),"reasoning_output_tokens":\#(reasoning),"total_tokens":0}}}"#
    }

    private func tokenCount(total: Int, last: Int, ago: TimeInterval = 300, limits: String = #"{"primary":{"used_percent":12.5,"window_minutes":10080,"resets_at":1791500000},"secondary":null,"plan_type":"prolite"}"#) -> String {
        func usage(_ n: Int) -> String {
            #"{"input_tokens":\#(n),"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":\#(n),"reasoning_output_tokens":0,"total_tokens":\#(2 * n)}"#
        }
        return #"{"timestamp":"\#(iso(ago))","ordinal":3,"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":\#(usage(total)),"last_token_usage":\#(usage(last)),"model_context_window":1},"rate_limits":\#(limits)}}"#
    }

    @discardableResult
    private func write(_ lines: [String], to name: String = "a.jsonl", folder: String = "sessions/2026/10/08") throws -> URL {
        let dir = home.appendingPathComponent(folder)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try Data(lines.map { $0 + "\n" }.joined().utf8).write(to: url)
        return url
    }

    private func append(_ line: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((line + "\n").utf8))
    }

    private func fetch(_ provider: CodexProvider) async throws -> ProviderSnapshot {
        try await provider.fetch(now: now)
    }

    @Test func readsTokenUsageRecords() async throws {
        // input_tokens includes cached_input_tokens. output_tokens includes reasoning_output_tokens.
        let line = usageRecord("r1", input: 1000, cached: 800, output: 50, reasoning: 30)
        try write([turnContext("gpt-6-sol"), line, "not json", line])
        let records = try await fetch(CodexProvider(home: home)).records
        #expect(records.count == 1)
        #expect(records[0].model == "gpt-6-sol")
        #expect(records[0].tokens == TokenCounts(input: 200, output: 50, cacheRead: 800))
    }

    @Test func readsOldTokenCountLinesOnce() async throws {
        // Codex repeats some token_count lines with the same total. Count them once.
        try write([turnContext("gpt-5.5"), tokenCount(total: 10, last: 10), tokenCount(total: 10, last: 10), tokenCount(total: 15, last: 5)])
        let records = try await fetch(CodexProvider(home: home)).records
        #expect(records.map(\.tokens.input).sorted() == [5, 10])
        #expect(records.allSatisfy { $0.model == "gpt-5.5" })
    }

    @Test func usesOnlyUsageRecordsWhenBothShapesExist() async throws {
        try write([turnContext("gpt-6-sol"), tokenCount(total: 50, last: 50), usageRecord("r1", input: 50, cached: 0, output: 50)])
        let records = try await fetch(CodexProvider(home: home)).records
        #expect(records.count == 1)
        #expect(records[0].tokens.input == 50)
    }

    @Test func takesLimitsFromNewestLine() async throws {
        try write([tokenCount(total: 1, last: 1, ago: 900)], to: "old.jsonl")
        let newest = #"{"primary":{"used_percent":40,"window_minutes":300,"resets_at":1791470000},"secondary":{"used_percent":70,"window_minutes":10080,"resets_at":1791900000}}"#
        try write([tokenCount(total: 1, last: 1, ago: 60, limits: newest), tokenCount(total: 2, last: 1, ago: 30, limits: "null")], to: "new.jsonl")
        try write([tokenCount(total: 1, last: 1, ago: 120, limits: #"{"primary":{"used_percent":5,"window_minutes":90,"resets_at":null}}"#)], to: "mid.jsonl")
        let limits = try await fetch(CodexProvider(home: home)).limits
        #expect(limits.map(\.name) == ["5-hour", "weekly"])
        #expect(limits.map(\.usedPercent) == [40, 70])
        #expect(limits[0].resetsAt == Date(timeIntervalSince1970: 1_791_470_000))
        #expect(limits.allSatisfy { $0.observedAt == now.addingTimeInterval(-60) })
    }

    @Test func namesOtherWindowsInMinutes() async throws {
        try write([tokenCount(total: 1, last: 1, limits: #"{"primary":{"used_percent":5,"window_minutes":90,"resets_at":null}}"#)])
        let limits = try await fetch(CodexProvider(home: home)).limits
        #expect(limits.map(\.name) == ["90-minute"])
        #expect(limits[0].resetsAt == nil)
    }

    @Test func readsAppendedLinesOnly() async throws {
        let url = try write([turnContext("gpt-6-sol"), usageRecord("r1", input: 1, cached: 0, output: 1)])
        let provider = CodexProvider(home: home)
        #expect(try await fetch(provider).records.count == 1)
        try append(usageRecord("r2", input: 2, cached: 0, output: 2), to: url)
        #expect(try await fetch(provider).records.count == 2)
        #expect(try await fetch(provider).records.count == 2)
    }

    @Test func dropsRecordsOfRewrittenFile() async throws {
        let url = try write([usageRecord("r1", input: 1, cached: 0, output: 1), usageRecord("r2", input: 2, cached: 0, output: 2)])
        let provider = CodexProvider(home: home)
        #expect(try await fetch(provider).records.count == 2)
        try FileManager.default.removeItem(at: url)
        try write([usageRecord("r3", input: 3, cached: 0, output: 3)])
        #expect(try await fetch(provider).records.map(\.tokens.input) == [3])
    }

    @Test func scansOnlyLast35Days() async throws {
        let old = try write([usageRecord("old-file", input: 1, cached: 0, output: 1)], to: "old.jsonl", folder: "archived_sessions")
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-36 * 86_400)], ofItemAtPath: old.path)
        try write([usageRecord("old-line", input: 2, cached: 0, output: 2, ago: 36 * 86_400), usageRecord("new", input: 3, cached: 0, output: 3)])
        let records = try await fetch(CodexProvider(home: home)).records
        #expect(records.map(\.tokens.input) == [3])
    }

    @Test func neverReturnsContent() async throws {
        try write([
            #"{"timestamp":"\#(iso(700))","ordinal":0,"type":"session_meta","payload":{"base_instructions":{"text":"SECRET-MARKER"}}}"#,
            turnContext("gpt-6-sol"),
            #"{"timestamp":"\#(iso(500))","ordinal":1,"type":"response_item","payload":{"type":"message","content":[{"type":"input_text","text":"SECRET-MARKER \"type\":\"token_count\""}]}}"#,
            usageRecord("r1", input: 1, cached: 0, output: 1),
            #"{"timestamp":"\#(iso(200))","ordinal":4,"type":"event_msg","payload":{"type":"agent_message","message":"SECRET-MARKER"}}"#,
        ])
        let snapshot = try await fetch(CodexProvider(home: home))
        #expect(snapshot.records.count == 1)
        #expect(!String(describing: snapshot).contains("SECRET-MARKER"))
    }

    @Test func throwsWhenSessionsFolderIsMissing() async {
        await #expect(throws: CocoaError.self) { try await fetch(CodexProvider(home: home)) }
    }

    /// Cold scan of the real Codex logs (TRD Section 7). Prints counts and time only. Never content.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TOKENBAR_REAL_SCAN"] == "1"))
    func coldScanOfRealLogs() async throws {
        let provider = CodexProvider()
        let now = Date()
        let clock = ContinuousClock()
        var snapshot: ProviderSnapshot?
        let cold = try await clock.measure { snapshot = try await provider.fetch(now: now) }
        let warm = try await clock.measure { _ = try await provider.fetch(now: now) }
        let home = CodexProvider.defaultHome
        let files = CodexProvider.logFiles(in: [home.appendingPathComponent("sessions"), home.appendingPathComponent("archived_sessions")],
                                           since: now.addingTimeInterval(-35 * 86_400))
        let bytes = files.reduce(0) { $0 + ((try? FileManager.default.attributesOfItem(atPath: $1)[.size]) as? Int ?? 0) }
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        _ = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) }
        }
        let snap = try #require(snapshot)
        print("""
            codex real scan: files=\(files.count) bytes=\(bytes / 1_000_000) MB records=\(snap.records.count) \
            models=\(Set(snap.records.map(\.model)).count) limitWindows=\(snap.limits.count) \
            cold=\(cold) warm=\(warm) peakRSS=\(info.resident_size_max / 1_000_000) MB
            """)
    }
}

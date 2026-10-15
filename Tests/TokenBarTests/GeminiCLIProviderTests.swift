import Foundation
import Testing
@testable import TokenBar

/// Synthetic fixtures only (TRD Section 12). No line comes from a real chat file.
@Suite struct GeminiCLIProviderTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("gemini-\(UUID().uuidString)")
    let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded())

    private func iso(_ secondsAgo: TimeInterval) -> String {
        Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(now.addingTimeInterval(-secondsAgo))
    }

    private let metadata = #"{"sessionId":"s1","projectHash":"h","startTime":"2026-10-14T10:00:00.000Z","lastUpdated":"2026-10-14T10:00:00.000Z","kind":"main"}"#

    private func gemini(_ id: String, input: Int = 100, output: Int = 10, cached: Int = 0, thoughts: Int? = nil, tool: Int? = nil,
                        model: String? = "gemini-2.5-pro", ago: TimeInterval = 300) -> String {
        let model = model.map { #","model":"\#($0)""# } ?? ""
        let extra = (thoughts.map { #","thoughts":\#($0)"# } ?? "") + (tool.map { #","tool":\#($0)"# } ?? "")
        return #"{"id":"\#(id)","timestamp":"\#(iso(ago))","type":"gemini","content":"SECRET-MARKER","thoughts":[{"subject":"SECRET-MARKER","description":"SECRET-MARKER","timestamp":"\#(iso(ago))"}],"toolCalls":[{"id":"t","name":"read_file","args":{"path":"SECRET-MARKER"},"status":"success","timestamp":"\#(iso(ago))"}]"#
            + #","tokens":{"input":\#(input),"output":\#(output),"cached":\#(cached)\#(extra),"total":0}\#(model)}"#
    }

    @discardableResult
    private func write(_ lines: [String], to name: String = "session-2026-10-14T10-00-abcd1234.jsonl", folder: String = "proj/chats") throws -> URL {
        let dir = root.appendingPathComponent(folder)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try Data(lines.map { $0 + "\n" }.joined().utf8).write(to: url)
        return url
    }

    private func records() async throws -> [UsageRecord] {
        try await GeminiCLIProvider(root: root).fetch(now: now).records
    }

    @Test func mapsTokens() async throws {
        // input includes cached. output excludes thoughts. tool counts as input.
        try write([metadata, gemini("m1", input: 1000, output: 50, cached: 800, thoughts: 30, tool: 20)])
        let records = try await records()
        #expect(records.count == 1)
        #expect(records[0].provider == .geminiCLI && records[0].model == "gemini-2.5-pro")
        #expect(records[0].timestamp == now.addingTimeInterval(-300))
        #expect(records[0].tokens == TokenCounts(input: 220, output: 80, cacheRead: 800))
    }

    @Test func clampsUncachedInputAtZero() async throws {
        try write([gemini("m1", input: 10, cached: 50, model: nil)])
        let records = try await records()
        #expect(records[0].tokens == TokenCounts(input: 0, output: 10, cacheRead: 50))
        #expect(records[0].model == "unknown")
    }

    @Test func lastLineForAMessageWins() async throws {
        let noTokens = #"{"id":"m1","timestamp":"\#(iso(300))","type":"gemini","content":"","model":"gemini-2.5-pro"}"#
        let nullTokens = #"{"id":"m1","timestamp":"\#(iso(300))","type":"gemini","content":"","tokens":null}"#
        try write([metadata, noTokens, gemini("m1", input: 5), gemini("m1", input: 7), nullTokens, gemini("m2", input: 9)])
        let records = try await records()
        #expect(records.map(\.tokens.input).sorted() == [7, 9])
    }

    @Test func skipsUserControlAndBadLines() async throws {
        try write([
            metadata,
            #"{"id":"u1","timestamp":"\#(iso(400))","type":"user","content":[{"text":"SECRET-MARKER \"tokens\":{\"input\":1}"}]}"#,
            #"{"id":"u2","timestamp":"\#(iso(400))","type":"user","tokens":{"input":1,"output":1,"cached":0,"total":2}}"#,
            #"{"$set":{"lastUpdated":"x","messages":[{"id":"z","type":"gemini","timestamp":"\#(iso(1))","tokens":{"input":1,"output":1,"cached":0,"total":2}}]}}"#,
            #"{"$patch":{"id":"m1","tokens":{"input":1,"output":1,"cached":0,"total":2}}}"#,
            #"{"$rewindTo":"m1"}"#,
            #"{"tokens":{"input":1,"output":1,"cached":0,"total":2}"#,
            "not json",
            gemini("m1", input: 3),
        ])
        let records = try await records()
        #expect(records.map(\.tokens.input) == [3])
    }

    @Test func readsSubagentChatsAndLegacyFiles() async throws {
        try write([metadata, gemini("m1", input: 1)])
        try write([metadata, gemini("m1", input: 2)], to: "sub-1.jsonl", folder: "proj/chats/parent-session")
        let legacy = #"{"sessionId":"s2","projectHash":"h","startTime":"x","lastUpdated":"x","messages":[{"id":"u1","timestamp":"\#(iso(500))","type":"user","content":"SECRET-MARKER"},\#(gemini("m1", input: 4))]}"#
        try write([legacy], to: "session-old.json", folder: "other/chats")
        let records = try await records()
        #expect(records.map(\.tokens.input).sorted() == [1, 2, 4])
    }

    @Test func skipsLegacyFileWithJSONLCopyAndFilesOutsideChats() async throws {
        let legacy = #"{"sessionId":"s","projectHash":"h","startTime":"x","lastUpdated":"x","messages":[\#(gemini("m1", input: 4))]}"#
        try write([legacy], to: "session-a.json")
        try write([metadata, gemini("m1", input: 4)], to: "session-a.jsonl")
        try write([gemini("c1", input: 99)], to: "checkpoint.jsonl", folder: "proj")
        let records = try await records()
        #expect(records.map(\.tokens.input) == [4])
    }

    @Test func readsAppendedLinesAndRewrittenFiles() async throws {
        let url = try write([metadata, gemini("m1", input: 1)])
        let provider = GeminiCLIProvider(root: root)
        #expect(try await provider.fetch(now: now).records.count == 1)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((gemini("m1", input: 5) + "\n" + gemini("m2", input: 6) + "\n").utf8))
        try handle.close()
        #expect(try await provider.fetch(now: now).records.map(\.tokens.input).sorted() == [5, 6])
        // The CLI rewrites a file with a temp file and a rename. The provider reads the new file again.
        try FileManager.default.removeItem(at: url)
        try write([metadata, gemini("m3", input: 8)])
        #expect(try await provider.fetch(now: now).records.map(\.tokens.input) == [8])
    }

    @Test func scansOnlyLast35Days() async throws {
        let old = try write([gemini("old-file", input: 1)], to: "old.jsonl")
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-36 * 86_400)], ofItemAtPath: old.path)
        try write([gemini("old-line", input: 2, ago: 36 * 86_400), gemini("new", input: 3)])
        let records = try await records()
        #expect(records.map(\.tokens.input) == [3])
    }

    @Test func neverReturnsContentOrLimits() async throws {
        try write([metadata, gemini("m1")])
        let snapshot = try await GeminiCLIProvider(root: root).fetch(now: now)
        #expect(snapshot.records.count == 1)
        #expect(snapshot.limits.isEmpty)
        #expect(!String(describing: snapshot).contains("SECRET-MARKER"))
    }

    @Test func throwsNotInstalledWhenRootIsMissing() async {
        let error = await #expect(throws: CocoaError.self) { try await GeminiCLIProvider(root: root).fetch(now: now) }
        #expect(error.map(DisplayBuilder.isNotInstalled) == true)
    }
}

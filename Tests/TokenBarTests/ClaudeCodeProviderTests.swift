import Foundation
import Testing
@testable import TokenBar

/// Synthetic fixtures only. Do not commit real logs.
@Suite struct ClaudeCodeProviderTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("claude-\(UUID().uuidString)")
    let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded()) // whole seconds: exact ISO 8601 round trip
    var file: URL { root.appendingPathComponent("-Users-me-proj/session.jsonl") }

    private func stamp(_ date: Date) -> String {
        Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(date) // real format: 2026-10-08T12:00:00.123Z
    }

    private func assistant(
        id: String, request: String? = "req_1", model: String = "claude-opus-5-5", at date: Date? = nil,
        input: Int = 10, output: Int = 20, usageExtra: String = "", extra: String = ""
    ) -> String {
        let req = request.map { #""requestId":"\#($0)","# } ?? ""
        return #"{"type":"assistant",\#(req)\#(extra)"timestamp":"\#(stamp(date ?? now))","message":{"id":"\#(id)","model":"\#(model)","role":"assistant","content":[{"type":"text","text":"SECRET-MARKER"}],"usage":{"input_tokens":\#(input),"output_tokens":\#(output)\#(usageExtra)}}}"#
    }

    private func write(_ lines: [String], to url: URL? = nil) throws {
        let url = url ?? file
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
    }

    private func append(_ lines: [String]) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((lines.joined(separator: "\n") + "\n").utf8))
    }

    private func fetch(_ provider: ClaudeCodeProvider) async throws -> [UsageRecord] {
        try await provider.fetch(now: now).records
    }

    @Test func readsAllTokenFields() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try write([
            assistant(id: "a", usageExtra: #","cache_read_input_tokens":30,"cache_creation_input_tokens":90,"cache_creation":{"ephemeral_5m_input_tokens":40,"ephemeral_1h_input_tokens":50}"#),
            assistant(id: "b", usageExtra: #","cache_creation_input_tokens":70"#),
        ])
        let records = try await fetch(ClaudeCodeProvider(roots: [root]))
        let byCacheRead = Dictionary(uniqueKeysWithValues: records.map { ($0.tokens.cacheRead, $0) })
        #expect(records.count == 2)
        #expect(byCacheRead[30]?.tokens == TokenCounts(input: 10, output: 20, cacheRead: 30, cacheWrite5m: 40, cacheWrite1h: 50))
        #expect(byCacheRead[0]?.tokens == TokenCounts(input: 10, output: 20, cacheWrite5m: 70))
        #expect(records.allSatisfy { $0.provider == .claudeCode && $0.model == "claude-opus-5-5" })
        #expect(abs(records[0].timestamp.timeIntervalSince(now)) < 0.001)
    }

    @Test func lastLineWinsForSameKey() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try write([
            assistant(id: "a", output: 1),
            assistant(id: "a", output: 5),
            assistant(id: "a", request: "req_2", output: 7),
            assistant(id: "b", request: nil, output: 3),
            assistant(id: "b", request: nil, output: 4),
        ])
        let provider = ClaudeCodeProvider(roots: [root])
        let outputs = try await fetch(provider).map(\.tokens.output).sorted()
        #expect(outputs == [4, 5, 7])
        // A second file repeats key "a:req_1". Keys stay across files.
        try write([assistant(id: "a", output: 9)], to: root.appendingPathComponent("-Users-me-proj/resumed.jsonl"))
        #expect(try await fetch(provider).map(\.tokens.output).sorted() == [4, 7, 9])
    }

    @Test func skipsSyntheticErrorAndNonAssistantLines() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try write([
            assistant(id: "s", model: "<synthetic>"),
            assistant(id: "e", extra: #""isApiErrorMessage":true,"#),
            #"{"type":"user","toolUseResult":{"type":"assistant"},"message":{"role":"user","content":"x"}}"#,
            #"{"type":"summary","summary":"x"}"#,
            #"{"type":"assistant", broken"#,
            assistant(id: "ok", extra: #""isSidechain":true,"#),
        ])
        #expect(try await fetch(ClaudeCodeProvider(roots: [root])).count == 1)
    }

    @Test func readsAppendedLinesOnNextFetch() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try write([assistant(id: "a")])
        let provider = ClaudeCodeProvider(roots: [root])
        #expect(try await fetch(provider).count == 1)
        try append([assistant(id: "b"), assistant(id: "a", output: 99)])
        let records = try await fetch(provider)
        #expect(records.map(\.tokens.output).sorted() == [20, 99])
    }

    @Test func dropsOldRecordsWhenFileRestarts() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try write([assistant(id: "a"), assistant(id: "b")])
        let provider = ClaudeCodeProvider(roots: [root])
        #expect(try await fetch(provider).count == 2)
        try FileManager.default.removeItem(at: file)
        try write([assistant(id: "c")])
        let records = try await fetch(provider)
        #expect(records.count == 1)
        try FileManager.default.removeItem(at: file)
        #expect(try await fetch(provider).isEmpty)
    }

    @Test func keepsOnlyLast35Days() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let day: TimeInterval = 24 * 3600
        try write([assistant(id: "new", at: now - 34 * day), assistant(id: "old", at: now - 36 * day)])
        let oldFile = root.appendingPathComponent("-Users-me-old/old.jsonl")
        try write([assistant(id: "skipped", at: now - 40 * day)], to: oldFile)
        try FileManager.default.setAttributes([.modificationDate: now - 40 * day], ofItemAtPath: oldFile.path)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: file.path)
        let records = try await fetch(ClaudeCodeProvider(roots: [root]))
        #expect(records.count == 1)
        #expect(records.first?.timestamp == now - 34 * day)
    }

    @Test func neverReturnsContent() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try write([
            #"{"type":"user","message":{"role":"user","content":"SECRET-MARKER prompt"}}"#,
            #"{"type":"last-prompt","lastPrompt":"SECRET-MARKER"}"#,
            assistant(id: "a"),
        ])
        let snapshot = try await ClaudeCodeProvider(roots: [root]).fetch(now: now)
        #expect(snapshot.records.count == 1)
        #expect(!String(describing: snapshot).contains("SECRET-MARKER"))
    }

    @Test func throwsWhenFolderIsMissing() async {
        await #expect(throws: ClaudeCodeProvider.Failure.self) {
            try await ClaudeCodeProvider(roots: [root]).fetch(now: now)
        }
    }

    @Test func addsClaudeConfigDir() {
        let roots = ClaudeCodeProvider.defaultRoots(environment: ["CLAUDE_CONFIG_DIR": "/tmp/cfg"])
        #expect(roots.map(\.path).contains("/tmp/cfg/projects"))
    }

    /// Run with `TOKENBAR_REAL_SCAN=1 swift test --filter coldScanOfRealLogs`. Prints counts only.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TOKENBAR_REAL_SCAN"] == "1"))
    func coldScanOfRealLogs() async throws {
        let roots = ClaudeCodeProvider.defaultRoots()
        let start = Date()
        var files = 0
        for root in roots {
            let all = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey])
            while let url = all?.nextObject() as? URL {
                let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                if url.pathExtension == "jsonl", let modified, modified >= start - 35 * 24 * 3600 { files += 1 }
            }
        }
        let clock = ContinuousClock()
        var snapshot: ProviderSnapshot?
        let elapsed = try await clock.measure {
            snapshot = try await ClaudeCodeProvider(roots: roots).fetch(now: start)
        }
        let records = snapshot?.records ?? []
        print("cold scan: files=\(files) records=\(records.count) models=\(Set(records.map(\.model)).count) seconds=\(elapsed)")
        #expect(!records.isEmpty)
    }
}

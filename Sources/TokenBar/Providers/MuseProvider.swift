import Foundation

/// Reads Meta Muse Code session files (TRD Section 5.8).
/// Decodes only record types, event kinds, timestamps, model names and token counts. Never prompt or response content.
/// The files have no limit data, so the provider returns no limits (D54).
actor MuseProvider: UsageProvider {
    nonisolated let id = ProviderID.muse

    /// `~/.local/share/muse/sessions`. A session file is `YYYY/MM/DD/<id>/session.jsonl`.
    /// A subagent file is `<id>/subagent/<child-id>/session.jsonl`.
    static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/share/muse/sessions")
    }

    private static let window: TimeInterval = 35 * 24 * 3600
    private static let marker = Data(#""model_completed""#.utf8)

    private let root: URL
    private var files: [String: FileState] = [:]

    /// The last path component of `root` must be `sessions`.
    init(root: URL = MuseProvider.defaultRoot) {
        self.root = root
    }

    func fetch(now: Date) async throws -> ProviderSnapshot {
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSURLErrorKey: root])
        }
        let start = now.addingTimeInterval(-Self.window)
        // Only session files. A folder below `sessions` with a leading dot is a derived view.
        let paths = CodexProvider.logFiles(in: [root], since: start).filter {
            $0.hasSuffix("/session.jsonl") && !("/" + ($0.components(separatedBy: "/sessions/").last ?? "")).contains("/.")
        }

        files = files.filter { paths.contains($0.key) }
        for path in paths {
            let url = URL(fileURLWithPath: path)
            var state = files[path] ?? FileState()
            var reader = state.reader
            try autoreleasepool {
                // A restarted file was truncated or replaced. Drop its old records and parse it again from the start.
                if try reader.readNewLines(at: url, { state.add(line: $0) }) {
                    state = FileState()
                    reader = JSONLTailReader()
                    _ = try reader.readNewLines(at: url) { state.add(line: $0) }
                }
            }
            state.reader = reader
            files[path] = state
        }

        let records = files.values.flatMap(\.records.values).filter { $0.timestamp >= start }
        return ProviderSnapshot(provider: .muse, records: records, limits: [], updatedAt: now)
    }

    /// The parse state of one session file.
    private struct FileState {
        var reader = JSONLTailReader()
        /// Key: the time, the model and the counts. A replayed line changes nothing.
        var records: [String: UsageRecord] = [:]

        mutating func add(line: Data) {
            // Only a `model_completed` event gives a record. Skip all other lines without decoding.
            // `goal_usage_attribution` and `workflow_child_lifecycle` repeat the same usage, so they do not count.
            guard line.range(of: MuseProvider.marker) != nil,
                  let record = try? MuseProvider.decoder.decode(Record.self, from: line),
                  record.payloadType == "runtime.session", record.payload?.kind == "run",
                  let event = record.payload?.event, event.kind == "model_completed",
                  let usage = event.usage, let micros = record.recordedAt else { return }
            // `input_tokens` includes the cache read. `output_tokens` includes the reasoning tokens.
            // Clamp first (D61): a corrupt value must not overflow the subtraction or the sums later.
            let cacheRead = max(TokenCounts.clamp(usage.cacheReadTokens ?? 0), TokenCounts.clamp(usage.cachedTokens ?? 0))
            let counts = TokenCounts(input: max(0, TokenCounts.clamp(usage.inputTokens) - cacheRead),
                                     output: TokenCounts.clamp(usage.outputTokens),
                                     cacheRead: cacheRead, cacheWrite5m: TokenCounts.clamp(usage.cacheWriteTokens ?? 0))
            // The model ID can have the provider prefix: "meta/muse-spark-1.3".
            let model = event.model.map { $0.hasPrefix("meta/") ? String($0.dropFirst(5)) : $0 } ?? "unknown"
            records["\(micros) \(model) \(counts.input) \(counts.output) \(counts.cacheRead)"] = UsageRecord(
                provider: .muse, model: model, timestamp: Date(timeIntervalSince1970: micros / 1_000_000), tokens: counts)
        }
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    // Only the fields in TRD Section 5.8. JSONDecoder drops all other keys, including prompts, replies and tool output.
    private struct Record: Decodable {
        let recordedAt: Double?  // microseconds since 1970
        let payloadType: String?
        let payload: Payload?
    }

    private struct Payload: Decodable {
        let kind: String?
        let event: Event?
    }

    private struct Event: Decodable {
        let kind: String?
        let model: String?
        let usage: Usage?
    }

    private struct Usage: Decodable {
        let inputTokens: Int
        let outputTokens: Int
        let cachedTokens: Int?
        let cacheReadTokens: Int?
        let cacheWriteTokens: Int?
    }
}

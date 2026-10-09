import Foundation

/// Reads token usage from the Claude Code JSONL logs (TRD Section 5.1).
/// The provider reads only token counts, model names and timestamps. It never decodes `message.content`.
actor ClaudeCodeProvider: UsageProvider {
    enum Failure: Error { case notFound }

    nonisolated let id = ProviderID.claudeCode
    private let roots: [URL]
    private let limitsFile: URL
    private var reader = JSONLTailReader()
    /// Deduplication key → newest record and the file that holds it. Keys stay across files.
    private var records: [String: (file: String, record: UsageRecord)] = [:]

    private static let window: TimeInterval = 35 * 24 * 3600
    private static let marker = Data(#""type":"assistant""#.utf8)

    /// Tests inject temporary locations.
    init(roots: [URL] = ClaudeCodeProvider.defaultRoots(), limitsFile: URL = ClaudeCodeLimits.defaultFile) {
        self.roots = roots
        self.limitsFile = limitsFile
    }

    static func defaultRoots(environment: [String: String] = ProcessInfo.processInfo.environment) -> [URL] {
        var roots = [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")]
        if let dir = environment["CLAUDE_CONFIG_DIR"], !dir.isEmpty {
            roots.append(URL(fileURLWithPath: dir).appendingPathComponent("projects"))
        }
        return roots
    }

    func fetch(now: Date) async throws -> ProviderSnapshot {
        let start = now.addingTimeInterval(-Self.window)
        let existing = roots.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { throw Failure.notFound }

        // Files that already gave records are read again, so the reader can detect a delete or a truncation.
        var paths = Set(records.values.map(\.file))
        for root in existing {
            let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey])
            while let url = files?.nextObject() as? URL {
                guard url.pathExtension == "jsonl",
                      let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                      modified >= start else { continue }
                paths.insert(url.path)
            }
        }

        for path in paths {
            var new: [(String, UsageRecord)] = []
            let restarted = try reader.readNewLines(at: URL(fileURLWithPath: path)) { line in
                if let entry = parse(line) { new.append(entry) }
            }
            if restarted { records = records.filter { $0.value.file != path } }
            for (key, record) in new { records[key] = (path, record) }
        }

        // Drop records older than the window, so memory does not grow while the app runs for months.
        records = records.filter { $0.value.record.timestamp >= start }
        return ProviderSnapshot(
            provider: id,
            records: records.values.map(\.record),
            limits: try ClaudeCodeLimits.read(from: limitsFile),
            updatedAt: now
        )
    }

    /// Returns nil for lines without token usage and for malformed lines.
    private func parse(_ line: Data) -> (String, UsageRecord)? {
        // memmem is much faster than `Data.range(of:)` on long lines. It saved about 0.6 s on the real cold scan.
        let hasMarker = line.withUnsafeBytes { raw in
            Self.marker.withUnsafeBytes { memmem(raw.baseAddress, raw.count, $0.baseAddress, $0.count) != nil }
        }
        guard hasMarker,
              let entry = try? Self.decoder.decode(Line.self, from: line),
              entry.type == "assistant", entry.isApiErrorMessage != true,
              entry.message.model != "<synthetic>" else { return nil }
        let usage = entry.message.usage
        let tokens = TokenCounts(
            input: usage.input_tokens,
            output: usage.output_tokens,
            cacheRead: usage.cache_read_input_tokens ?? 0,
            cacheWrite5m: usage.cache_creation?.ephemeral_5m_input_tokens ?? usage.cache_creation_input_tokens ?? 0,
            cacheWrite1h: usage.cache_creation?.ephemeral_1h_input_tokens ?? 0
        )
        let key = entry.requestId.map { "\(entry.message.id):\($0)" } ?? entry.message.id
        return (key, UsageRecord(provider: .claudeCode, model: entry.message.model, timestamp: entry.timestamp, tokens: tokens))
    }

    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = try? fractional.parse(text) { return date }
            return try Date.ISO8601FormatStyle().parse(text)
        }
        return decoder
    }()

    // Declare only the TRD 5.1 fields. JSONDecoder ignores all other keys, `message.content` too.
    private struct Line: Decodable {
        let type: String
        let timestamp: Date
        let requestId: String?
        let isApiErrorMessage: Bool?
        let message: Message
    }

    private struct Message: Decodable {
        let id: String
        let model: String
        let usage: Usage
    }

    private struct Usage: Decodable {
        let input_tokens: Int
        let output_tokens: Int
        let cache_read_input_tokens: Int?
        let cache_creation_input_tokens: Int?
        let cache_creation: CacheCreation?
    }

    private struct CacheCreation: Decodable {
        let ephemeral_5m_input_tokens: Int?
        let ephemeral_1h_input_tokens: Int?
    }
}

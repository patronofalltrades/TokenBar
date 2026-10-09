import Foundation

/// Reads Codex CLI session logs (TRD Section 5.2).
/// Decodes only token counts, model names, timestamps and limits. Never prompt or response content.
actor CodexProvider: UsageProvider {
    nonisolated let id = ProviderID.codex

    /// The Codex home folder: `$CODEX_HOME`, else `~/.codex`.
    static var defaultHome: URL {
        ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    private static let window: TimeInterval = 35 * 24 * 3600
    private static let markers = ["token_usage_record", "token_count", "turn_context"]
        .map { Data("\"type\":\"\($0)\"".utf8) }

    private let home: URL
    private var files: [String: FileState] = [:]

    init(home: URL = CodexProvider.defaultHome) {
        self.home = home
    }

    func fetch(now: Date) async throws -> ProviderSnapshot {
        let sessions = home.appendingPathComponent("sessions")
        guard FileManager.default.fileExists(atPath: sessions.path) else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSURLErrorKey: sessions])
        }
        let start = now.addingTimeInterval(-Self.window)
        let paths = Self.logFiles(in: [sessions, home.appendingPathComponent("archived_sessions")], since: start)

        // A file that left the window or the disk loses its records and its reader state.
        files = files.filter { paths.contains($0.key) }
        for path in paths {
            let url = URL(fileURLWithPath: path)
            var state = files[path] ?? FileState()
            var reader = state.reader
            // FileHandle returns autoreleased buffers. Without a pool per file, a cold scan holds all of them.
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

        let records = files.values.flatMap(\.records).filter { $0.timestamp >= start }
        let limits = files.values.compactMap(\.limits).max { $0.observedAt < $1.observedAt }?.windows ?? []
        return ProviderSnapshot(provider: .codex, records: records, limits: limits, updatedAt: now)
    }

    /// Paths of the `.jsonl` files in `folders` that changed at or after `start`.
    static func logFiles(in folders: [URL], since start: Date) -> Set<String> {
        Set(folders.flatMap { folder -> [String] in
            let items = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])
            return (items?.allObjects as? [URL] ?? []).compactMap { url in
                guard url.pathExtension == "jsonl",
                      let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                      modified >= start else { return nil }
                return url.path
            }
        })
    }

    /// The parse state of one log file. Every update is keyed, so a replayed line changes nothing.
    private struct FileState {
        var reader = JSONLTailReader()
        var model = "unknown"
        var usageRecords: [String: UsageRecord] = [:]      // key: response_id
        var tokenCountRecords: [Usage: UsageRecord] = [:]  // key: total_token_usage. Codex repeats some token_count lines.
        var limits: (observedAt: Date, windows: [LimitWindow])?

        /// Double count rule: if the file has `token_usage_record` lines, use only those.
        var records: [UsageRecord] {
            usageRecords.isEmpty ? Array(tokenCountRecords.values) : Array(usageRecords.values)
        }

        mutating func add(line: Data) {
            // The marker starts within the first 86 bytes on all 45,900 real marker lines (2026-10-09).
            // Search only the line head: a full-line search was most of the cold-scan time.
            guard CodexProvider.markers.contains(where: { line.prefix(256).range(of: $0) != nil }),
                  let entry = try? CodexProvider.decoder.decode(Line.self, from: line),
                  let time = try? CodexProvider.timestamp.parse(entry.timestamp) else { return }
            let payload = entry.payload

            switch (entry.type, payload.type) {
            case ("turn_context", _):
                if let model = payload.model { self.model = model }
            case ("token_usage_record", _):
                if let id = payload.responseId, let usage = payload.usage {
                    usageRecords[id] = record(usage, at: time)
                }
            case ("event_msg", "token_count"):
                if let info = payload.info {
                    tokenCountRecords[info.totalTokenUsage] = record(info.lastTokenUsage, at: time)
                }
                if let rates = payload.rateLimits, time >= limits?.observedAt ?? .distantPast {
                    let windows = [rates.primary, rates.secondary].compactMap { $0 }
                    limits = (time, windows.map { $0.window(observedAt: time) })
                }
            default:
                break
            }
        }

        /// `input_tokens` includes `cached_input_tokens`. `output_tokens` includes `reasoning_output_tokens`.
        /// Real logs agree: `total_tokens == input_tokens + output_tokens`.
        /// Cache writes stay 0. `cache_write_input_tokens` was 0 in all real lines, and it is not clear
        /// that it is separate from `input_tokens`. OpenAI does not charge cache writes separately.
        private func record(_ usage: Usage, at time: Date) -> UsageRecord {
            let cached = min(usage.cachedInputTokens, usage.inputTokens)
            let tokens = TokenCounts(input: usage.inputTokens - cached, output: usage.outputTokens, cacheRead: cached)
            return UsageRecord(provider: .codex, model: model, timestamp: time, tokens: tokens)
        }
    }

    private static let timestamp = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    // Only the fields in TRD Section 5.2. JSONDecoder drops all other keys, including content.
    private struct Line: Decodable {
        let timestamp: String
        let type: String
        let payload: Payload
    }

    private struct Payload: Decodable {
        let type: String?
        let model: String?
        let responseId: String?
        let usage: Usage?
        let info: Info?
        let rateLimits: RateLimits?
    }

    private struct Info: Decodable {
        let totalTokenUsage: Usage
        let lastTokenUsage: Usage
    }

    private struct Usage: Decodable, Hashable {
        let inputTokens: Int
        let cachedInputTokens: Int
        let outputTokens: Int
    }

    private struct RateLimits: Decodable {
        let primary: Rate?
        let secondary: Rate?
    }

    private struct Rate: Decodable {
        let usedPercent: Double
        let windowMinutes: Int
        let resetsAt: Double?

        func window(observedAt: Date) -> LimitWindow {
            let name = switch windowMinutes {
            case 300: "5-hour"
            case 10080: "weekly"
            default: "\(windowMinutes)-minute"
            }
            return LimitWindow(name: name, usedPercent: usedPercent,
                               resetsAt: resetsAt.map { Date(timeIntervalSince1970: $0) }, observedAt: observedAt)
        }
    }
}

import Foundation

/// Reads Google Gemini CLI chat files (TRD Section 5.6).
/// Decodes only message IDs, types, timestamps, model names and token counts. Never prompt or response content.
/// The files have no limit data, so the provider returns no limits (D50).
actor GeminiCLIProvider: UsageProvider {
    nonisolated let id = ProviderID.geminiCLI

    /// `~/.gemini/tmp`. Chat files are in `<project>/chats/`, subagent chats in `<project>/chats/<parent-id>/`.
    static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".gemini/tmp")
    }

    private static let window: TimeInterval = 35 * 24 * 3600
    private static let marker = Data(#""tokens":{"#.utf8)

    private let root: URL
    private var files: [String: FileState] = [:]

    init(root: URL = GeminiCLIProvider.defaultRoot) {
        self.root = root
    }

    func fetch(now: Date) async throws -> ProviderSnapshot {
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSURLErrorKey: root])
        }
        let start = now.addingTimeInterval(-Self.window)
        // Only chat files. Other files in the project folders (for example checkpoints) contain content.
        // The CLI copies a resumed legacy `.json` session to `<name>.jsonl`. Then skip the `.json` file.
        let paths = CodexProvider.logFiles(in: [root], since: start, extensions: ["jsonl", "json"]).filter {
            $0.contains("/chats/") && !($0.hasSuffix(".json") && FileManager.default.fileExists(atPath: $0 + "l"))
        }

        files = files.filter { paths.contains($0.key) }
        for path in paths {
            let url = URL(fileURLWithPath: path)
            if url.pathExtension == "json" {
                // The CLI writes only `.jsonl` files now, so a legacy file does not change. Read it one time.
                guard files[path] == nil else { continue }
                var state = FileState()
                autoreleasepool {
                    let legacy = (try? Data(contentsOf: url)).flatMap { try? Self.decoder.decode(Legacy.self, from: $0) }
                    legacy?.messages.forEach { state.add($0) }
                }
                files[path] = state
                continue
            }
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
        return ProviderSnapshot(provider: .geminiCLI, records: records, limits: [], updatedAt: now)
    }

    /// The parse state of one chat file.
    private struct FileState {
        var reader = JSONLTailReader()
        /// Key: message ID. The CLI writes a message again when it adds the tokens. The last line wins.
        var records: [String: UsageRecord] = [:]

        mutating func add(line: Data) {
            // Only a line with token counts can give a record. Skip all other lines without decoding.
            guard line.range(of: GeminiCLIProvider.marker) != nil,
                  let message = try? GeminiCLIProvider.decoder.decode(Message.self, from: line) else { return }
            add(message)
        }

        /// Metadata lines and control lines (`$set`, `$patch`, `$rewindTo`) have no `type`, so they give no record.
        mutating func add(_ message: Message) {
            guard message.type == "gemini", let id = message.id, let tokens = message.tokens,
                  let text = message.timestamp, let time = try? GeminiCLIProvider.timestamp.parse(text) else { return }
            // `input` includes `cached`. `output` does not include `thoughts`.
            let counts = TokenCounts(input: max(0, tokens.input + (tokens.tool ?? 0) - tokens.cached),
                                     output: tokens.output + (tokens.thoughts ?? 0), cacheRead: tokens.cached)
            records[id] = UsageRecord(provider: .geminiCLI, model: message.model ?? "unknown", timestamp: time, tokens: counts)
        }
    }

    private static let timestamp = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let decoder = JSONDecoder()

    // Only the fields in TRD Section 5.6. JSONDecoder drops all other keys, including content, thoughts and tool calls.
    private struct Message: Decodable {
        let id: String?
        let timestamp: String?
        let type: String?
        let model: String?
        let tokens: Tokens?
    }

    private struct Tokens: Decodable {
        let input: Int
        let output: Int
        let cached: Int
        let thoughts: Int?
        let tool: Int?
    }

    /// A legacy `.json` session: one object with all messages.
    private struct Legacy: Decodable {
        let messages: [Message]
    }
}

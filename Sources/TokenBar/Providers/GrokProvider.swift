import Foundation

/// Reads the xAI Grok Build log (TRD Section 5.7).
/// Decodes only event names, timestamps, session IDs, model names and token counts. Never prompt or response content.
/// The files have no limit data, so the provider returns no limits (D54).
actor GrokProvider: UsageProvider {
    nonisolated let id = ProviderID.grok

    /// `GROK_HOME`, else `~/.grok`.
    static var defaultHome: URL {
        if let home = ProcessInfo.processInfo.environment["GROK_HOME"], !home.isEmpty {
            return URL(fileURLWithPath: home)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: ".grok")
    }

    private static let window: TimeInterval = 35 * 24 * 3600
    private static let event = "shell.turn.inference_done"
    private static let marker = Data(event.utf8)

    private let home: URL
    private var reader = JSONLTailReader()
    /// A set: the log can repeat a row. Equal rows count one time.
    private var rows: Set<Row> = []
    /// Key: session ID.
    private var models: [String: String] = [:]
    /// Key: session ID. When the search for its summary found nothing. Search again after `retryAfter` (D61).
    private var missing: [String: Date] = [:]
    private static let retryAfter: TimeInterval = 300

    init(home: URL = GrokProvider.defaultHome) {
        self.home = home
    }

    func fetch(now: Date) async throws -> ProviderSnapshot {
        guard FileManager.default.fileExists(atPath: home.path) else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSURLErrorKey: home])
        }
        let start = now.addingTimeInterval(-Self.window)
        // A rotated or truncated log starts again at 0. The old rows stay: they are real usage, and the set drops repeats.
        // ponytail: the history is only as long as the log since the app started. Read `updates.jsonl` if users lose days.
        var new: [Row] = []
        try autoreleasepool {
            _ = try reader.readNewLines(at: home.appending(path: "logs/unified.jsonl")) { line in
                if let row = Self.row(line) { new.append(row) }
            }
        }
        rows.formUnion(new)
        rows = rows.filter { $0.time >= start }

        let live = Set(rows.map(\.session))
        models = models.filter { live.contains($0.key) }
        missing = missing.filter { live.contains($0.key) }
        var names: [String: String] = [:]
        for session in live { names[session] = model(of: session, now: now) }
        let records = rows.map {
            UsageRecord(provider: .grok, model: names[$0.session] ?? "unknown", timestamp: $0.time, tokens: $0.tokens)
        }
        return ProviderSnapshot(provider: .grok, records: records, limits: [], updatedAt: now)
    }

    private struct Row: Hashable {
        let session: String
        let time: Date
        let tokens: TokenCounts
    }

    private static func row(_ line: Data) -> Row? {
        // Only an inference row gives usage. Skip all other lines without decoding.
        guard line.range(of: marker) != nil, let entry = try? decoder.decode(Entry.self, from: line),
              entry.msg == event, let ctx = entry.ctx, let time = entry.ts?.date else { return nil }
        // `prompt_tokens` includes the cached tokens. `completion_tokens` includes the reasoning tokens.
        // Clamp first (D61): a corrupt value must not overflow the sums later.
        let prompt = TokenCounts.clamp(ctx.promptTokens)
        let cached = min(TokenCounts.clamp(ctx.cachedPromptTokens ?? 0), prompt)
        return Row(session: entry.sid ?? "", time: time,
                   tokens: TokenCounts(input: prompt - cached, output: TokenCounts.clamp(ctx.completionTokens), cacheRead: cached))
    }

    /// The model of a session, from `sessions/<encoded folder>/<session ID>/summary.json`. The log row has no model.
    /// "unknown" has no price, so the popover says "Some models not counted".
    private func model(of session: String, now: Date) -> String {
        if let known = models[session] { return known }
        // A session without a summary cost one file read in each project folder. Do not repeat it at each refresh.
        if let at = missing[session], now.timeIntervalSince(at) < Self.retryAfter { return "unknown" }
        // The ID becomes a path component. Permit only letters, digits, "-" and "_".
        guard !session.isEmpty,
              session.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return "unknown" }
        let folders = (try? FileManager.default.contentsOfDirectory(at: home.appending(path: "sessions"),
                                                                     includingPropertiesForKeys: nil)) ?? []
        for folder in folders {
            guard let data = try? Data(contentsOf: folder.appending(path: session).appending(path: "summary.json")),
                  let summary = try? Self.decoder.decode(Summary.self, from: data),
                  let model = summary.currentModelId ?? summary.info?.currentModelId ?? summary.modelId ?? summary.info?.modelId
            else { continue }
            models[session] = model
            missing[session] = nil
            return model
        }
        missing[session] = now
        return "unknown"
    }

    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plain = Date.ISO8601FormatStyle()
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    // Only the fields in TRD Section 5.7. JSONDecoder drops all other keys.
    private struct Entry: Decodable {
        let ts: Stamp?
        let msg: String?
        let sid: String?
        let ctx: Context?
    }

    private struct Context: Decodable {
        let promptTokens: Int
        let completionTokens: Int
        let cachedPromptTokens: Int?
    }

    /// `ts` is ISO 8601 text in the known samples. A number is seconds or milliseconds since 1970.
    private struct Stamp: Decodable {
        let date: Date?

        init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let text = try? value.decode(String.self) {
                date = (try? GrokProvider.fractional.parse(text)) ?? (try? GrokProvider.plain.parse(text))
            } else {
                let number = try value.decode(Double.self)
                date = Date(timeIntervalSince1970: number >= 1e12 ? number / 1000 : number)
            }
        }
    }

    private struct Summary: Decodable {
        let currentModelId: String?
        let modelId: String?
        let info: Info?

        struct Info: Decodable {
            let currentModelId: String?
            let modelId: String?
        }
    }
}

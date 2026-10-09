import Foundation

/// The `--statusline` mode (TRD Section 5.1, bridge steps 1 to 4).
/// Claude Code sends session JSON on stdin. The bridge keeps only `rate_limits`.
/// Do not store `session_name`, paths or other fields. They can hold prompt text.
enum StatuslineBridge {
    private struct Input: Decodable {
        let rate_limits: ClaudeCodeLimits.Stored?
    }

    static func main() {
        let input = (try? FileHandle.standardInput.readToEnd()) ?? Data()
        print(run(input: input, file: ClaudeCodeLimits.defaultFile, now: Date()))
    }

    /// Writes the limits file and returns the line for Claude Code to show. Never throws.
    /// Input without `rate_limits` (no Pro or Max plan, or before the first API response) writes nothing.
    static func run(input: Data, file: URL, now: Date) -> String {
        guard var limits = (try? JSONDecoder().decode(Input.self, from: input))?.rate_limits,
              limits.five_hour != nil || limits.seven_day != nil else { return "TokenBar" }

        // Claude Code drops a window after its reset time. Keep the old window, so the app can show it as reset.
        let old = try? JSONDecoder().decode(ClaudeCodeLimits.Stored.self, from: Data(contentsOf: file))
        limits.five_hour = limits.five_hour ?? old?.five_hour
        limits.seven_day = limits.seven_day ?? old?.seven_day
        limits.observed_at = now.timeIntervalSince1970

        // A failed write must not break the Claude Code status line. The app then shows the older values with their age.
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(limits).write(to: file, options: .atomic)

        let parts = [("5h", limits.five_hour), ("wk", limits.seven_day)].compactMap { label, window in
            window.map { "\(label) \(Int($0.used_percentage.rounded()))%" }
        }
        return (["TokenBar"] + parts).joined(separator: " · ")
    }
}

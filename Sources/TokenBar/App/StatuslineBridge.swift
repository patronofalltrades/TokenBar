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
        let line = run(input: input, file: ClaudeCodeLimits.defaultFile, now: Date())
        print(chain(input: input, previousFile: ClaudeConnect.defaultPreviousFile) ?? line)
    }

    /// Runs the status line that was active before Connect (D39) with the same input, and returns its output.
    /// Returns nil if no status line is saved, or on a non-zero exit, empty output or timeout. Never throws.
    static func chain(input: Data, previousFile: URL) -> String? {
        guard let saved = try? Data(contentsOf: previousFile),
              let command = (try? JSONSerialization.jsonObject(with: saved) as? [String: Any])?["command"] as? String
        else { return nil }

        // A file, not a pipe, for stdout: a pipe read can block if a child process keeps the pipe open.
        let out = FileManager.default.temporaryDirectory.appending(path: "tokenbar-chain-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }
        guard FileManager.default.createFile(atPath: out.path, contents: nil),
              let stdout = try? FileHandle(forWritingTo: out) else { return nil }
        defer { try? stdout.close() }

        let stdin = Pipe()
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        signal(SIGPIPE, SIG_IGN)  // A command that does not read stdin must not stop TokenBar.
        guard (try? process.run()) != nil else { return nil }

        let writer = stdin.fileHandleForWriting
        DispatchQueue.global().async {
            try? writer.write(contentsOf: input)
            try? writer.close()
        }
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning, Date() < deadline { usleep(10_000) }
        if process.isRunning {
            process.terminate()
            return nil
        }

        guard process.terminationStatus == 0, var text = try? String(contentsOf: out, encoding: .utf8) else { return nil }
        while text.last?.isNewline == true { text.removeLast() }
        return text.isEmpty ? nil : text
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

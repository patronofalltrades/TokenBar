import Foundation

/// Reads only the new complete lines of JSONL files (TRD Section 7).
/// A provider keeps one value of this type inside its actor.
/// The reader does not decode JSON. It never logs line content.
struct JSONLTailReader: Sendable {
    private struct FileState: Sendable {
        var device: dev_t
        var inode: ino_t
        var offset: UInt64
        var partial = Data()
    }

    private var files: [String: FileState] = [:]

    /// Returns the complete lines that were added since the last read of `url`.
    /// `restarted` is true when the reader dropped its old state for the file.
    /// Then the caller must drop the records that it read from that file before.
    /// Causes: the file was truncated, replaced (new inode) or deleted.
    /// A missing file gives no lines. The reader forgets the file.
    /// Bytes after the last newline stay in a buffer until their newline arrives.
    mutating func readNewLines(at url: URL) throws -> (lines: [Data], restarted: Bool) {
        let path = url.path
        var info = stat()
        guard stat(path, &info) == 0 else {
            if errno == ENOENT { return ([], files.removeValue(forKey: path) != nil) }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let size = UInt64(info.st_size)

        var restarted = false
        var state = files[path] ?? FileState(device: info.st_dev, inode: info.st_ino, offset: 0)
        if state.device != info.st_dev || state.inode != info.st_ino || size < state.offset {
            state = FileState(device: info.st_dev, inode: info.st_ino, offset: 0)
            restarted = true
        }
        guard size != state.offset || restarted else { return ([], false) }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: state.offset)
        let chunk = try handle.readToEnd() ?? Data()
        state.offset += UInt64(chunk.count)

        // The last piece is the bytes after the last newline: empty or a partial line.
        var pieces = (state.partial + chunk).split(separator: 0x0A, omittingEmptySubsequences: false)
        state.partial = Data(pieces.removeLast())
        files[path] = state

        let lines = pieces.filter { !$0.isEmpty }.map { Data($0) }
        return (lines, restarted)
    }
}

import Foundation

/// Reads only the new complete lines of JSONL files (TRD Section 7).
/// A provider keeps one value of this type inside its actor.
/// The reader does not decode JSON. It never logs line content.
struct JSONLTailReader: Sendable {
    private struct FileState: Sendable {
        var device: dev_t
        var inode: ino_t
        var offset: UInt64
        var partial: [UInt8] = []
    }

    private var files: [String: FileState] = [:]
    private let chunkSize: Int

    /// Tests set a small `chunkSize` to make lines cross chunk boundaries.
    init(chunkSize: Int = 1 << 20) {
        self.chunkSize = chunkSize
    }

    /// Calls `body` once for each complete, non-empty line that was added since the last read of `url`.
    /// The reader reads in chunks of `chunkSize` bytes, so memory does not grow with the file size.
    /// Returns true when the reader dropped its old state for the file.
    /// Then the caller must drop the records that it read from that file before.
    /// Causes: the file was truncated, replaced (new inode) or deleted.
    /// A missing file gives no lines. The reader forgets the file.
    /// Bytes after the last newline stay in a buffer until their newline arrives.
    /// If `body` throws, the reader keeps its old state. The next read gives the same lines again.
    mutating func readNewLines(at url: URL, _ body: (Data) throws -> Void) throws -> Bool {
        let path = url.path
        var info = stat()
        guard stat(path, &info) == 0 else {
            if errno == ENOENT { return files.removeValue(forKey: path) != nil }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let size = UInt64(info.st_size)

        var restarted = false
        var state = files[path] ?? FileState(device: info.st_dev, inode: info.st_ino, offset: 0)
        if state.device != info.st_dev || state.inode != info.st_ino || size < state.offset {
            state = FileState(device: info.st_dev, inode: info.st_ino, offset: 0)
            restarted = true
        }
        guard size != state.offset || restarted else { return false }

        // POSIX reads into one reused buffer. FileHandle gave a new autoreleased Data for each chunk.
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: chunkSize, alignment: 1)
        defer { buffer.deallocate() }
        let base = buffer.baseAddress!

        while true {
            let count = pread(fd, base, chunkSize, off_t(state.offset))
            if count < 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            if count == 0 { break }
            state.offset += UInt64(count)
            var start = 0
            while let match = memchr(base + start, 0x0A, count - start) {
                let end = base.distance(to: match)
                if state.partial.isEmpty {
                    if end > start { try body(Data(bytes: base + start, count: end - start)) }
                } else {
                    state.partial.append(contentsOf: buffer[start..<end])
                    try body(Data(state.partial))
                    state.partial = []
                }
                start = end + 1
            }
            state.partial.append(contentsOf: buffer[start..<count])
        }
        files[path] = state
        return restarted
    }
}

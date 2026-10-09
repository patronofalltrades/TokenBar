import Foundation
import Testing
@testable import TokenBar

@Suite struct JSONLTailReaderTests {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("tail-\(UUID().uuidString).jsonl")
    var reader = JSONLTailReader()

    private func write(_ text: String) throws {
        try Data(text.utf8).write(to: url)
    }

    private func append(_ text: String) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    private mutating func read() throws -> (lines: [String], restarted: Bool) {
        var lines: [String] = []
        let restarted = try reader.readNewLines(at: url) { lines.append(String(decoding: $0, as: UTF8.self)) }
        return (lines, restarted)
    }

    @Test mutating func readsOnlyAppendedLines() throws {
        try write("a\nb\n")
        #expect(try read().lines == ["a", "b"])
        #expect(try read().lines == [])
        try append("c\n")
        #expect(try read().lines == ["c"])
        try FileManager.default.removeItem(at: url)
    }

    @Test mutating func keepsPartialLineUntilNewline() throws {
        try write("a\n{\"par")
        #expect(try read().lines == ["a"])
        try append("tial\":1}")
        #expect(try read().lines == [])
        try append("\nb\n")
        #expect(try read().lines == ["{\"partial\":1}", "b"])
        try FileManager.default.removeItem(at: url)
    }

    @Test mutating func restartsAfterTruncation() throws {
        try write("old-1\nold-2\n")
        _ = try read()
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 0)
        try handle.close()
        try append("new\n")
        let result = try read()
        #expect(result.lines == ["new"])
        #expect(result.restarted)
        try FileManager.default.removeItem(at: url)
    }

    @Test mutating func restartsAfterReplacement() throws {
        try write("old\n")
        _ = try read()
        let other = url.appendingPathExtension("tmp")
        try Data("new-1\nnew-2\n".utf8).write(to: other)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: other)
        let result = try read()
        #expect(result.lines == ["new-1", "new-2"])
        #expect(result.restarted)
        try FileManager.default.removeItem(at: url)
    }

    @Test mutating func emptyFileGivesNoLines() throws {
        try write("")
        let result = try read()
        #expect(result.lines == [])
        #expect(!result.restarted)
        try append("a\n")
        #expect(try read().lines == ["a"])
        try FileManager.default.removeItem(at: url)
    }

    @Test mutating func missingFileGivesNoLinesAndForgetsState() throws {
        #expect(try read().lines == [])
        try write("a\n")
        _ = try read()
        try FileManager.default.removeItem(at: url)
        let gone = try read()
        #expect(gone.lines == [])
        #expect(gone.restarted)
        #expect(try read().restarted == false)
    }

    @Test mutating func readsLinesAcrossChunkBoundaries() throws {
        reader = JSONLTailReader(chunkSize: 4)
        try write("first-line\nsecond\nx\npart")
        #expect(try read().lines == ["first-line", "second", "x"])
        try append("ial\n")
        #expect(try read().lines == ["partial"])
        try FileManager.default.removeItem(at: url)
    }

    @Test mutating func handlesNewlineAtChunkEndAndLongLines() throws {
        reader = JSONLTailReader(chunkSize: 4)
        // "abc\n" ends exactly at the first chunk end. The second line is longer than two chunks.
        // Only "\n" ends a line, so "\r" stays in the line.
        try write("abc\n0123456789\nxy\r\n")
        #expect(try read().lines == ["abc", "0123456789", "xy\r"])
        try FileManager.default.removeItem(at: url)
    }

    @Test mutating func throwingBodyKeepsOldState() throws {
        try write("a\nb\n")
        struct Stop: Error {}
        #expect(throws: Stop.self) { try reader.readNewLines(at: url) { _ in throw Stop() } }
        #expect(try read().lines == ["a", "b"])
        try FileManager.default.removeItem(at: url)
    }
}

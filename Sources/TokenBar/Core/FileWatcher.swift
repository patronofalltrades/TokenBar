import CoreServices
import Foundation

/// Calls `changed` on the main queue with the changed paths, after files change under `paths` (IES-225).
/// FSEvents groups the changes of `latency` seconds into one call. No polling.
final class FileWatcher: @unchecked Sendable {  // the stream is set one time and used only on the main queue
    private var stream: FSEventStreamRef?
    private let changed: @MainActor ([String]) -> Void

    /// Nil when no path exists.
    init?(paths: [URL], latency: TimeInterval = 1.5, changed: @escaping @MainActor ([String]) -> Void) {
        self.changed = changed
        let existing = paths.map(\.path).filter { FileManager.default.fileExists(atPath: $0) }
        guard !existing.isEmpty else { return nil }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            let changed = (0..<count).map { String(cString: paths.assumingMemoryBound(to: UnsafePointer<CChar>.self)[$0]) }
            MainActor.assumeIsolated { watcher.changed(changed) }
        }
        guard let stream = FSEventStreamCreate(nil, callback, &context, existing as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency,
                                               FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone))
        else { return nil }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}

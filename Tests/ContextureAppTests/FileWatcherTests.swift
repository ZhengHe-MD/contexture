import Foundation
import Testing
@testable import ContextureApp

/// FileWatcher calls back on its own background queue while the test reads
/// from its own thread — a plain `var` would be an unsynchronized race.
private final class ChangeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    var current: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

@Suite struct FileWatcherTests {
    private func temporaryFile(contents: String = "initial") -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ctx-watch-\(UUID().uuidString.prefix(8)).md")
        try! contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Polls rather than sleeping a fixed amount: DispatchSource file-system
    /// events are asynchronous, and this keeps the test both fast in the
    /// common case and not flaky under load. FileWatcher's events arrive on
    /// its own background queue, so plain polling (no run-loop pumping) is
    /// enough regardless of which thread the test itself runs on.
    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return condition()
    }

    @Test func firesOnAnInPlaceWrite() {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let counter = ChangeCounter()
        let watcher = FileWatcher(url: url) { counter.increment() }
        #expect(watcher != nil)

        try! "changed".write(to: url, atomically: false, encoding: .utf8)

        #expect(waitUntil { counter.current > 0 })
        watcher?.stop()
    }

    @Test func firesOnAnAtomicReplaceViaRename() {
        // The common "safe save" pattern: write to a temp file, then rename
        // it over the original. This invalidates the original inode rather
        // than writing to it, which is exactly the case FileWatcher exists
        // to handle (see its doc comment).
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let counter = ChangeCounter()
        let watcher = FileWatcher(url: url) { counter.increment() }
        #expect(watcher != nil)

        let replacementURL = url.deletingLastPathComponent().appendingPathComponent("ctx-watch-replacement-\(UUID().uuidString.prefix(8)).md")
        try! "replaced atomically".write(to: replacementURL, atomically: true, encoding: .utf8)
        _ = try! FileManager.default.replaceItemAt(url, withItemAt: replacementURL)

        #expect(waitUntil { counter.current > 0 })
        #expect((try? String(contentsOf: url, encoding: .utf8)) == "replaced atomically")
        watcher?.stop()
    }

    @Test func continuesWatchingAfterAnAtomicReplace() {
        // Prove the reopen-on-rename logic actually keeps working, not just
        // that it fires once: a *second* external write after the atomic
        // replace must still be observed.
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let counter = ChangeCounter()
        let watcher = FileWatcher(url: url) { counter.increment() }

        let replacementURL = url.deletingLastPathComponent().appendingPathComponent("ctx-watch-replacement-\(UUID().uuidString.prefix(8)).md")
        try! "first replacement".write(to: replacementURL, atomically: true, encoding: .utf8)
        _ = try! FileManager.default.replaceItemAt(url, withItemAt: replacementURL)
        #expect(waitUntil { counter.current > 0 })

        let countAfterFirstChange = counter.current
        try! "second, in-place write".write(to: url, atomically: false, encoding: .utf8)
        #expect(waitUntil { counter.current > countAfterFirstChange })

        watcher?.stop()
    }

    @Test func returnsNilForANonexistentPath() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ctx-watch-does-not-exist-\(UUID().uuidString).md")
        let watcher = FileWatcher(url: url) {}
        #expect(watcher == nil)
    }

    @Test func stopSuppressesFurtherNotifications() {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let counter = ChangeCounter()
        let watcher = FileWatcher(url: url) { counter.increment() }
        watcher?.stop()

        try! "after stop".write(to: url, atomically: false, encoding: .utf8)
        // A generous fixed wait here (rather than waitUntil) is deliberate:
        // proving a *negative* means waiting out the full window regardless.
        _ = waitUntil(timeout: 0.3) { false }
        #expect(counter.current == 0)
    }
}

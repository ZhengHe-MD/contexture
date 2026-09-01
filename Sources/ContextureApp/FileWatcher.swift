import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Watches a single file path for changes made by another process — an
/// Agent Host writing to the Document with its own tools
/// (docs/architecture/selection-bridge.md "Persistence and Document
/// authority": "Contexture is not the authority over the live Document").
///
/// Handles the common "atomic replace" save pattern (write a temp file,
/// rename over the original) as well as plain in-place writes: a rename-
/// over invalidates the original inode without necessarily firing a `.write`
/// event on the descriptor watching it, so on `.delete`/`.rename` this
/// reopens at the same path to keep watching whatever now lives there.
final class FileWatcher {
    private let url: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    // A dedicated queue rather than .main: this must keep working
    // regardless of whether anything is pumping the main run loop (e.g. in
    // a plain command-line test process), and the callback itself may hop
    // to main if it needs to.
    private let queue = DispatchQueue(label: "app.contexture.file-watcher")

    init?(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        guard openAndWatch() else { return nil }
    }

    deinit {
        stop()
    }

    @discardableResult
    private func openAndWatch() -> Bool {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return false }
        fileDescriptor = fd

        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: queue
        )
        newSource.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = newSource.data
            if flags.contains(.delete) || flags.contains(.rename) {
                self.teardownSource()
                _ = self.openAndWatch()
            }
            self.onChange()
        }
        newSource.setCancelHandler { [fd] in
            close(fd)
        }
        newSource.resume()
        source = newSource
        return true
    }

    private func teardownSource() {
        source?.cancel()
        source = nil
    }

    func stop() {
        teardownSource()
    }
}

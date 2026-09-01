import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// A tiny buffered reader over a raw file descriptor, so the byte-at-a-time
/// HTTP parser in HTTPMessage.swift doesn't issue one `read(2)` per byte.
private final class BufferedFileDescriptorReader {
    private let fd: Int32
    private var buffer: [UInt8] = []
    private var offset = 0

    init(fd: Int32) {
        self.fd = fd
    }

    func readByte() -> UInt8? {
        if offset >= buffer.count {
            var chunk = [UInt8](repeating: 0, count: 4096)
            let n = chunk.withUnsafeMutableBytes { pointer in
                read(fd, pointer.baseAddress, pointer.count)
            }
            guard n > 0 else { return nil }
            buffer = Array(chunk[0..<n])
            offset = 0
        }
        defer { offset += 1 }
        return buffer[offset]
    }
}

/// Transport is HTTP over a user-only Unix domain socket at mode 0600
/// (docs/architecture/selection-bridge.md, "Local security boundary").
/// Filesystem permissions are the entire authentication mechanism — no
/// credential is generated or checked at this layer.
final class UnixSocketServer {
    enum ServerError: Error {
        case socketCreationFailed
        case pathTooLong
        case bindFailed(String)
        case listenFailed
        case permissionsFailed
    }

    private let socketPath: String
    private var listenFD: Int32 = -1
    private var acceptThread: Thread?
    private let stateLock = NSLock()
    private var isRunning = false

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    /// Starts accepting connections on a background thread. `handle` is
    /// invoked once per request, on a fresh thread per connection — the
    /// Bridge only ever serves a handful of local, low-frequency callers,
    /// so a thread-per-connection model keeps this simple and avoids
    /// reactor/event-loop machinery this doesn't need.
    func start(handle: @escaping (HTTPRequest) -> HTTPResponse) throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !isRunning else { return }

        let directory = (socketPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        // A stale socket file from a previous run must not block bind().
        unlink(socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ServerError.socketCreationFailed }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            close(fd)
            throw ServerError.pathTooLong
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { rawPointer in
            let base = rawPointer.baseAddress!.assumingMemoryBound(to: UInt8.self)
            for (index, byte) in pathBytes.enumerated() {
                base[index] = byte
            }
            base[pathBytes.count] = 0
        }

        let bindResult = withUnsafePointer(to: &addr) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            let message = String(cString: strerror(errno))
            close(fd)
            throw ServerError.bindFailed(message)
        }

        // User-only: a different local user must not be able to connect at
        // all, let alone read Selection contents.
        guard chmod(socketPath, 0o600) == 0 else {
            close(fd)
            throw ServerError.permissionsFailed
        }

        guard listen(fd, 16) == 0 else {
            close(fd)
            throw ServerError.listenFailed
        }

        listenFD = fd
        isRunning = true

        let thread = Thread { [weak self] in
            self?.acceptLoop(handle: handle)
        }
        thread.name = "contexture.selection-bridge.accept"
        thread.start()
        acceptThread = thread
    }

    func stop() {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard isRunning else { return }
        isRunning = false
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
        unlink(socketPath)
    }

    private func acceptLoop(handle: @escaping (HTTPRequest) -> HTTPResponse) {
        while true {
            stateLock.lock()
            let fd = listenFD
            let running = isRunning
            stateLock.unlock()
            guard running, fd >= 0 else { return }

            let clientFD = accept(fd, nil, nil)
            guard clientFD >= 0 else {
                // A closed listening socket surfaces as an accept() error;
                // anything else is a transient local condition, keep serving.
                stateLock.lock()
                let stillRunning = isRunning
                stateLock.unlock()
                if !stillRunning { return }
                continue
            }

            Thread.detachNewThread { [clientFD] in
                Self.serve(clientFD: clientFD, handle: handle)
            }
        }
    }

    private static func serve(clientFD: Int32, handle: @escaping (HTTPRequest) -> HTTPResponse) {
        defer { close(clientFD) }
        let reader = BufferedFileDescriptorReader(fd: clientFD)
        let response: HTTPResponse
        do {
            let request = try HTTPRequestParser.parse(readByte: reader.readByte)
            response = handle(request)
        } catch {
            response = .empty(400)
        }
        let data = response.serialize()
        data.withUnsafeBytes { pointer in
            var remaining = pointer.count
            var base = pointer.baseAddress!
            while remaining > 0 {
                let n = write(clientFD, base, remaining)
                guard n > 0 else { return }
                remaining -= n
                base = base.advanced(by: n)
            }
        }
    }
}

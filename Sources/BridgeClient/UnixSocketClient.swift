import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// A minimal, self-contained HTTP/1.1-over-Unix-domain-socket client. This
/// deliberately does not share code with SelectionBridge's server-side
/// parser (that type is internal to that target) — the wire contract is
/// small, self-controlled, and duplicating a few dozen lines here keeps
/// Agent Adapters from depending on the whole Bridge server implementation
/// just to talk to it.
///
/// Every failure mode — connection refused, timeout, malformed response —
/// surfaces as `nil`, never a thrown error. Callers (Agent Adapters) must
/// treat "the Bridge is unreachable" identically to "nothing is Armed":
/// docs/architecture/selection-bridge.md's injection-decision table maps
/// both to "inject nothing", and there is no case where an Adapter should
/// let a Bridge failure become visible to the writer.
enum UnixSocketClient {
    struct RawResponse {
        let statusCode: Int
        let body: Data
    }

    static func send(
        socketPath: String,
        method: String,
        path: String,
        jsonBody: Data,
        timeout: TimeInterval
    ) -> RawResponse? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var timeoutValue = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - timeout.rounded(.down)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeoutValue, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeoutValue, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { rawPointer in
            let base = rawPointer.baseAddress!.assumingMemoryBound(to: UInt8.self)
            for (index, byte) in pathBytes.enumerated() {
                base[index] = byte
            }
            base[pathBytes.count] = 0
        }

        let connectResult = withUnsafePointer(to: &addr) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else { return nil }

        var head = "\(method) \(path) HTTP/1.1\r\n"
        head += "Host: contexture\r\n"
        head += "Content-Type: application/json\r\n"
        head += "Content-Length: \(jsonBody.count)\r\n"
        head += "Connection: close\r\n\r\n"
        var request = Data(head.utf8)
        request.append(jsonBody)

        let sendSucceeded = request.withUnsafeBytes { pointer -> Bool in
            var remaining = pointer.count
            guard var base = pointer.baseAddress else { return remaining == 0 }
            while remaining > 0 {
                let n = write(fd, base, remaining)
                guard n > 0 else { return false }
                remaining -= n
                base = base.advanced(by: n)
            }
            return true
        }
        guard sendSucceeded else { return nil }

        return readResponse(fd: fd)
    }

    private static func readResponse(fd: Int32) -> RawResponse? {
        var buffer: [UInt8] = []
        var offset = 0

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

        func readLine() -> String? {
            var line: [UInt8] = []
            while true {
                guard let byte = readByte() else { return nil }
                if byte == UInt8(ascii: "\n") {
                    if line.last == UInt8(ascii: "\r") { line.removeLast() }
                    return String(decoding: line, as: UTF8.self)
                }
                line.append(byte)
                if line.count > 8192 { return nil }
            }
        }

        guard let statusLine = readLine() else { return nil }
        let statusParts = statusLine.split(separator: " ", maxSplits: 2)
        guard statusParts.count >= 2, let statusCode = Int(statusParts[1]) else { return nil }

        var headers: [String: String] = [:]
        while true {
            guard let line = readLine() else { return nil }
            if line.isEmpty { break }
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let name = line[line.startIndex..<colonIndex].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let contentLength = headers["content-length"].flatMap(Int.init) ?? 0
        var body = [UInt8]()
        body.reserveCapacity(contentLength)
        for _ in 0..<contentLength {
            guard let byte = readByte() else { return nil }
            body.append(byte)
        }

        return RawResponse(statusCode: statusCode, body: Data(body))
    }
}

import Foundation

/// A parsed HTTP/1.1 request. The Bridge's wire contract is small and
/// entirely self-controlled (one process writes the client, another the
/// server), so this only implements what that contract needs: a
/// request-line, headers up to the blank line, and a fixed-length body
/// read via Content-Length. No chunked transfer-encoding.
struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
}

struct HTTPResponse {
    let statusCode: Int
    let body: Data

    static func json(_ statusCode: Int, _ object: some Encodable) -> HTTPResponse {
        let data = (try? JSONEncoder().encode(object)) ?? Data("{}".utf8)
        return HTTPResponse(statusCode: statusCode, body: data)
    }

    static func empty(_ statusCode: Int) -> HTTPResponse {
        HTTPResponse(statusCode: statusCode, body: Data())
    }

    private static let reasonPhrases: [Int: String] = [
        200: "OK", 204: "No Content", 400: "Bad Request",
        403: "Forbidden", 404: "Not Found", 413: "Payload Too Large",
        429: "Too Many Requests", 500: "Internal Server Error",
    ]

    func serialize() -> Data {
        let reason = Self.reasonPhrases[statusCode] ?? "Unknown"
        var head = "HTTP/1.1 \(statusCode) \(reason)\r\n"
        head += "Content-Type: application/json\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n"
        head += "\r\n"
        var data = Data(head.utf8)
        data.append(body)
        return data
    }
}

enum HTTPRequestParser {
    /// Content past a configurable cap is rejected outright rather than
    /// buffered — this is the local-only payload cap from the architecture
    /// doc's "Local security boundary" (rate-limit reads and cap payload
    /// size), independent of the per-snapshot/total envelope caps issue #8
    /// adds for rendering.
    static let maxBodyBytes = 4 * 1024 * 1024

    enum ParseError: Error {
        case malformedRequestLine
        case headerTooLarge
        case bodyTooLarge
        case connectionClosed
    }

    /// Reads exactly one HTTP request from `readByte`, which should block
    /// until a byte is available and return nil on EOF.
    static func parse(readByte: () -> UInt8?) throws -> HTTPRequest {
        var lineBuffer: [UInt8] = []
        var headerBlock: [UInt8] = []

        func readLine() throws -> String {
            lineBuffer.removeAll(keepingCapacity: true)
            while true {
                guard let byte = readByte() else { throw ParseError.connectionClosed }
                if byte == UInt8(ascii: "\n") {
                    if lineBuffer.last == UInt8(ascii: "\r") { lineBuffer.removeLast() }
                    return String(decoding: lineBuffer, as: UTF8.self)
                }
                lineBuffer.append(byte)
                if lineBuffer.count > 8192 { throw ParseError.headerTooLarge }
            }
        }

        let requestLine = try readLine()
        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { throw ParseError.malformedRequestLine }
        let method = String(parts[0])
        let path = String(parts[1])

        var headers: [String: String] = [:]
        while true {
            let line = try readLine()
            if line.isEmpty { break }
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let name = line[line.startIndex..<colonIndex].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
            headerBlock.append(contentsOf: line.utf8)
        }

        let contentLength = headers["content-length"].flatMap(Int.init) ?? 0
        guard contentLength <= maxBodyBytes else { throw ParseError.bodyTooLarge }

        var body = [UInt8]()
        body.reserveCapacity(contentLength)
        for _ in 0..<contentLength {
            guard let byte = readByte() else { throw ParseError.connectionClosed }
            body.append(byte)
        }

        return HTTPRequest(method: method, path: path, headers: headers, body: Data(body))
    }
}

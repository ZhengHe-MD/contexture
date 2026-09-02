import CryptoKit
import Foundation

/// A content hash of a Document's on-disk bytes. Publishing flushes to disk
/// before Arming (ADR-0003), so this hash always describes on-disk content
/// and doubles as a conflict detector.
public struct RevisionHash: Sendable, Hashable, Codable, CustomStringConvertible {
    public let hexDigest: String

    public init(hexDigest: String) {
        self.hexDigest = hexDigest
    }

    public init(contentBytes: [UInt8]) {
        let digest = SHA256.hash(data: Data(contentBytes))
        self.hexDigest = digest.map { String(format: "%02x", $0) }.joined()
    }

    public init(contentBytes: Data) {
        let digest = SHA256.hash(data: contentBytes)
        self.hexDigest = digest.map { String(format: "%02x", $0) }.joined()
    }

    public var description: String { hexDigest }
}

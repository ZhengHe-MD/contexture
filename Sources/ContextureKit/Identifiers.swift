import Foundation

/// Opaque identifier for a Document open in Contexture. Never derived from or
/// convertible back to a filesystem path.
public struct DocumentID: Sendable, Hashable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init() {
        self.rawValue = UUID().uuidString
    }

    public var description: String { rawValue }
}

/// Opaque identifier for a Selection Snapshot.
public struct SnapshotID: Sendable, Hashable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init() {
        self.rawValue = UUID().uuidString
    }

    public var description: String { rawValue }
}

/// Identity of the editor window a Selection was made in, used to attribute
/// Snapshots when several windows are open. Opaque outside ContextureKit.
public struct SourceWindowID: Sendable, Hashable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init() {
        self.rawValue = UUID().uuidString
    }

    public var description: String { rawValue }
}

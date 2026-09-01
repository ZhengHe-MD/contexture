import Foundation

/// An immutable, revision-bound record of a Selection that may be shared
/// with an agent prompt. Fields match the Selection Snapshot contract in
/// docs/architecture/selection-bridge.md.
public struct SelectionSnapshot: Sendable, Hashable, Codable {
    public let id: SnapshotID
    public let documentID: DocumentID
    /// Exact selected Source bytes, UTF-8 encoded.
    public let sourceBytes: Data
    public let format: FormatTag
    /// Document path relative to its Working Root. Absolute paths never
    /// leave the Bridge (ADR-0004).
    public let relativePath: String
    /// Hash of the on-disk Document content this Snapshot was taken from.
    public let revision: RevisionHash
    public let byteRange: SourceByteRange
    public let displayLine: Int?
    public let displayColumn: Int?
    public let headingTrail: [String]
    public let sharingMode: SharingMode
    public let createdAt: Date
    public let sourceWindow: SourceWindowID
    /// Monotonically increasing per-Document selection version. A new
    /// Selection in the same Document supersedes the previous Snapshot only
    /// when its version is greater.
    public let version: Int

    public init(
        id: SnapshotID = SnapshotID(),
        documentID: DocumentID,
        sourceBytes: Data,
        format: FormatTag,
        relativePath: String,
        revision: RevisionHash,
        byteRange: SourceByteRange,
        displayLine: Int? = nil,
        displayColumn: Int? = nil,
        headingTrail: [String] = [],
        sharingMode: SharingMode,
        createdAt: Date,
        sourceWindow: SourceWindowID,
        version: Int
    ) {
        self.id = id
        self.documentID = documentID
        self.sourceBytes = sourceBytes
        self.format = format
        self.relativePath = relativePath
        self.revision = revision
        self.byteRange = byteRange
        self.displayLine = displayLine
        self.displayColumn = displayColumn
        self.headingTrail = headingTrail
        self.sharingMode = sharingMode
        self.createdAt = createdAt
        self.sourceWindow = sourceWindow
        self.version = version
    }

    /// Whitespace-only and zero-length Selections must never be Armed or
    /// injected. See "Injection decision" in the architecture doc.
    public var isEffectivelyEmpty: Bool {
        sourceBytes.isEmpty || String(decoding: sourceBytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

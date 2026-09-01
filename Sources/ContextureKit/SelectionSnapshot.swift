import Foundation

/// An immutable, revision-bound record of a Selection that may be shared
/// with an agent prompt. Fields match the Selection Snapshot contract in
/// docs/architecture/selection-bridge.md.
public struct SelectionSnapshot: Sendable, Hashable {
    public let id: SnapshotID
    public let documentID: DocumentID
    /// Exact selected Source bytes, UTF-8 encoded.
    public let sourceBytes: Data
    public let format: FormatTag
    /// Document path relative to its Working Root. Computed by the Bridge
    /// at read time (ADR-0004, issue #8) against the requesting caller's
    /// Working Root — the value here at publish time is a placeholder only
    /// ever observed if something reads snapshots without going through
    /// that scoping.
    public let relativePath: String
    /// The Document's real filesystem path, used only inside the Bridge to
    /// decide whether it lies under a caller's Working Root and to compute
    /// `relativePath` at read time. **Deliberately excluded from this
    /// type's `Codable` conformance below** — ADR-0004: "Absolute paths
    /// never leave the Bridge." This must never reach an Adapter, a log, or
    /// any other process boundary.
    public let absolutePath: String
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
        absolutePath: String,
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
        self.absolutePath = absolutePath
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

    /// Returns a copy with `relativePath` replaced — used by the Bridge to
    /// fill in the Working-Root-relative path at read time (issue #8) and
    /// by envelope truncation (also issue #8) to cap `sourceBytes`. Never
    /// changes `absolutePath` — callers outside SelectionBridge cannot
    /// construct or observe a snapshot with a different one than they
    /// started with, since nothing here re-exposes it over the wire.
    public func withRelativePath(_ newRelativePath: String) -> SelectionSnapshot {
        copy(relativePath: newRelativePath, sourceBytes: sourceBytes)
    }

    public func withSourceBytes(_ newSourceBytes: Data) -> SelectionSnapshot {
        copy(relativePath: relativePath, sourceBytes: newSourceBytes)
    }

    private func copy(relativePath: String, sourceBytes: Data) -> SelectionSnapshot {
        SelectionSnapshot(
            id: id, documentID: documentID, sourceBytes: sourceBytes, format: format,
            relativePath: relativePath, absolutePath: absolutePath, revision: revision,
            byteRange: byteRange, displayLine: displayLine, displayColumn: displayColumn,
            headingTrail: headingTrail, sharingMode: sharingMode, createdAt: createdAt,
            sourceWindow: sourceWindow, version: version
        )
    }

    /// Whitespace-only and zero-length Selections must never be Armed or
    /// injected. See "Injection decision" in the architecture doc.
    public var isEffectivelyEmpty: Bool {
        sourceBytes.isEmpty || String(decoding: sourceBytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

extension SelectionSnapshot: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, documentID, sourceBytes, format, relativePath, revision, byteRange
        case displayLine, displayColumn, headingTrail, sharingMode, createdAt, sourceWindow, version
        // absolutePath is intentionally absent: see its doc comment above.
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(SnapshotID.self, forKey: .id)
        documentID = try container.decode(DocumentID.self, forKey: .documentID)
        sourceBytes = try container.decode(Data.self, forKey: .sourceBytes)
        format = try container.decode(FormatTag.self, forKey: .format)
        relativePath = try container.decode(String.self, forKey: .relativePath)
        // Never present on the wire — a decoded snapshot (only ever
        // exercised by the /publish HTTP route, which the app itself never
        // actually uses in process) has no absolute path to scope-match
        // against, by construction.
        absolutePath = ""
        revision = try container.decode(RevisionHash.self, forKey: .revision)
        byteRange = try container.decode(SourceByteRange.self, forKey: .byteRange)
        displayLine = try container.decodeIfPresent(Int.self, forKey: .displayLine)
        displayColumn = try container.decodeIfPresent(Int.self, forKey: .displayColumn)
        headingTrail = try container.decode([String].self, forKey: .headingTrail)
        sharingMode = try container.decode(SharingMode.self, forKey: .sharingMode)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        sourceWindow = try container.decode(SourceWindowID.self, forKey: .sourceWindow)
        version = try container.decode(Int.self, forKey: .version)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(documentID, forKey: .documentID)
        try container.encode(sourceBytes, forKey: .sourceBytes)
        try container.encode(format, forKey: .format)
        try container.encode(relativePath, forKey: .relativePath)
        // absolutePath deliberately not encoded — see its doc comment.
        try container.encode(revision, forKey: .revision)
        try container.encode(byteRange, forKey: .byteRange)
        try container.encodeIfPresent(displayLine, forKey: .displayLine)
        try container.encodeIfPresent(displayColumn, forKey: .displayColumn)
        try container.encode(headingTrail, forKey: .headingTrail)
        try container.encode(sharingMode, forKey: .sharingMode)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(sourceWindow, forKey: .sourceWindow)
        try container.encode(version, forKey: .version)
    }
}

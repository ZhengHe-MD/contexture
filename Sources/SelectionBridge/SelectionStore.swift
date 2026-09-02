import ContextureKit
import Foundation

/// In-memory store of Armed Selection Snapshots, at most one per Document.
///
/// This is deliberately the minimal slice issue #3 needs: publish replaces
/// whatever was Armed for that Document, read returns everything Armed, and
/// ack consumes (removes) what was actually delivered. It does not yet
/// know about disk flushing / revision staleness (ADR-0003, issue #7), the
/// full Arming lifecycle or Sharing Mode Off (issue #6), or Working Root
/// scoping (issue #8) — those refine this store's behavior, not replace it.
public final class SelectionStore: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshotsByDocument: [DocumentID: SelectionSnapshot] = [:]

    public init() {}

    @discardableResult
    public func publish(_ snapshot: SelectionSnapshot) -> Int {
        lock.lock()
        defer { lock.unlock() }
        snapshotsByDocument[snapshot.documentID] = snapshot
        return snapshot.version
    }

    /// Explicit clear. If `version` is given, only clears when it still
    /// matches what's Armed — a newer Selection may already have
    /// superseded it.
    public func clear(documentID: DocumentID, version: Int? = nil) {
        lock.lock()
        defer { lock.unlock() }
        if let version, snapshotsByDocument[documentID]?.version != version {
            return
        }
        snapshotsByDocument.removeValue(forKey: documentID)
    }

    /// Every currently Armed, non-empty snapshot, most-recently-selected
    /// first. Not yet scoped to a Working Root — see issue #8.
    public func read() -> [SelectionSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        return snapshotsByDocument.values
            .filter { !$0.isEffectivelyEmpty }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Removes the named snapshots so Next Prompt content cannot leak into
    /// a later prompt. Only removes a snapshot if it is still the one
    /// Armed for its Document — a newer Selection made between read and
    /// ack must survive.
    public func ack(snapshotIDs: [SnapshotID]) {
        lock.lock()
        defer { lock.unlock() }
        let idSet = Set(snapshotIDs)
        for (documentID, snapshot) in snapshotsByDocument where idSet.contains(snapshot.id) {
            snapshotsByDocument.removeValue(forKey: documentID)
        }
    }
}

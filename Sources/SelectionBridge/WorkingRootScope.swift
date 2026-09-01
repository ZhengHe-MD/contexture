import ContextureKit
import Foundation

/// Scopes and caps what `read()` discloses to one caller's Working Root
/// (docs/adr/0004-scope-snapshots-to-the-working-root.md). Kept separate
/// from `SelectionStore`, which only knows about raw Arming state — this is
/// about what is safe and appropriate to hand to a *particular* caller.
///
/// The reversal ADR-0004 documents ("never expose an inventory of open
/// Documents") is safe only because of this scoping: a Document under the
/// Working Root is one the caller could already read with its own tools, so
/// disclosing it reveals nothing new. An unscoped or unmatched caller must
/// get nothing, not a degraded "best effort" answer — see `apply(to:workingRoot:)`.
public enum WorkingRootScope {
    /// A single Snapshot's Source is capped this far before "visible
    /// truncation" (a trailing marker in the Source text itself) kicks in.
    /// Public so the conformance harness (issue #9) can size its own
    /// truncation-cap test case against the real limit rather than a
    /// duplicated guess.
    public static let maxSnapshotBytes = 32_000
    /// Total across every block in one `read()` response. Most-recent-first
    /// ordering (SelectionStore.read() already guarantees this) means
    /// exceeding this drops the least-recent Selections, not arbitrary ones.
    public static let maxTotalBytes = 128_000

    /// `snapshots` must already be ordered most-recently-selected first.
    /// Returns `[]` outright for a missing/empty Working Root — there is no
    /// "return everything" fallback; an unscoped caller is treated the same
    /// as one whose Working Root matches nothing.
    static func apply(to snapshots: [SelectionSnapshot], workingRoot: String?) -> [SelectionSnapshot] {
        guard let workingRoot, !workingRoot.isEmpty else { return [] }
        let normalizedRoot = normalize(workingRoot)
        guard !normalizedRoot.isEmpty, normalizedRoot != "/" else { return [] }

        var result: [SelectionSnapshot] = []
        var totalBytes = 0

        for snapshot in snapshots {
            guard let relative = relativePath(of: snapshot.absolutePath, under: normalizedRoot) else { continue }

            let scoped = cap(snapshot.withRelativePath(relative))
            guard totalBytes + scoped.sourceBytes.count <= maxTotalBytes else { break }
            totalBytes += scoped.sourceBytes.count
            result.append(scoped)
        }
        return result
    }

    /// Lexically normalizes both sides (resolves `.`/`..`, trailing
    /// slashes) and compares path *components*, never raw string prefixes —
    /// a Working Root of `/Users/writer/project` must not spuriously match
    /// a sibling directory like `/Users/writer/project-other`. A Document
    /// must be strictly inside the root (more components than the root
    /// itself), not the root path verbatim.
    private static func relativePath(of absolutePath: String, under normalizedRoot: String) -> String? {
        guard !absolutePath.isEmpty else { return nil }
        let pathComponents = normalize(absolutePath).split(separator: "/")
        let rootComponents = normalizedRoot.split(separator: "/")
        guard pathComponents.count > rootComponents.count,
              Array(pathComponents.prefix(rootComponents.count)) == rootComponents else {
            return nil
        }
        return pathComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }

    private static func normalize(_ path: String) -> String {
        (path as NSString).standardizingPath
    }

    private static func cap(_ snapshot: SelectionSnapshot) -> SelectionSnapshot {
        guard snapshot.sourceBytes.count > maxSnapshotBytes else { return snapshot }
        let marker = Data(
            "\n\n[Contexture: selection truncated, showing \(maxSnapshotBytes) of \(snapshot.sourceBytes.count) bytes]".utf8
        )
        let budget = max(0, maxSnapshotBytes - marker.count)
        var truncated = snapshot.sourceBytes.prefix(budget)
        // Never cut a UTF-8 byte sequence mid-character.
        while !truncated.isEmpty, String(data: truncated, encoding: .utf8) == nil {
            truncated = truncated.dropLast()
        }
        return snapshot.withSourceBytes(Data(truncated) + marker)
    }
}

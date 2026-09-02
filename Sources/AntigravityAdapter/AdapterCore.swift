import BridgeClient
import ContextureKit
import Foundation

/// The documented Antigravity `PreInvocation` fields this adapter needs.
/// Antigravity supplies every mounted workspace as an absolute path, so the
/// adapter queries the Bridge once per root and de-duplicates snapshots when
/// roots overlap. The legacy identity/root fields remain optional so an older
/// locally installed hook can fail open during an upgrade.
struct PreInvocationInput: Decodable {
    let conversationId: String?
    let workspacePaths: [String]?
    let invocationNum: Int?

    // Backward-compatible aliases used by the pre-2.11 experimental adapter.
    let turnId: String?
    let promptEventId: String?
    let cwd: String?
}

/// One entry of Antigravity's `injectSteps` array. Only `ephemeralMessage`
/// is modeled — the one step kind the research doc names — since this
/// Adapter never has a reason to emit any other step kind.
struct InjectStep: Encodable {
    let ephemeralMessage: String
}

/// The has-content shape: `{"injectSteps": [{"ephemeralMessage": "..."}]}`.
struct HookOutputWithInjection: Encodable {
    let injectSteps: [InjectStep]
}

/// The no-content shape. Deliberately a struct with no stored properties
/// so `JSONEncoder` produces the literal bytes `{}` — an empty JSON
/// object, not an omitted stdout write. Per docs/research/
/// agent-compatibility.md "Neutral output is supported": "Antigravity
/// returns an empty object or omits `injectSteps`." This Adapter always
/// writes *something* (unlike Claude Code, where "write nothing" is
/// itself the neutral result) so `injectSteps` can be verified absent
/// from a real, well-formed JSON object rather than absent because
/// nothing was written at all.
struct EmptyHookOutput: Encodable {}

/// The adapter's three translations (docs/architecture/selection-bridge.md
/// "Adapter seam"), as a pure function over injected read/ack so it's
/// testable without a real socket or process. The executable entry point
/// (AdapterMain.swift) supplies real stdin bytes and a real BridgeClient;
/// this never touches I/O directly.
///
/// This is the one Adapter the ticket (#11) calls the most likely to
/// "expose a flaw in the Bridge's Consumption keying rather than in the
/// adapter itself": Antigravity's `PreInvocation` can fire several times
/// per user turn, so at-most-once injection has to hold across repeated
/// calls. That guarantee is *not* built here — the Bridge's Consumption
/// (`ack`) already permanently removes a Snapshot from the store the
/// first time it is successfully acked (Sources/SelectionBridge/
/// SelectionStore.swift `ack(snapshotIDs:)`), so a second `read` after a
/// successful `ack`, from this process or any other caller, returns
/// nothing — regardless of what `turnID`/`consumptionID` string is
/// passed. This function still calls `read` then `ack` in the ordinary
/// way and still chooses the best identity it has (see below), because
/// that identity is meaningful for diagnostics and for any future Bridge
/// that does key on it — it just isn't what makes double-injection
/// impossible today.
enum AntigravityAdapterCore {
    /// Returns the exact bytes to write to stdout — never `nil`. Unlike
    /// Claude Code's contract (nil literally means "write nothing"),
    /// Antigravity's neutral result is a specific JSON shape: an empty
    /// object with `injectSteps` absent. This function never throws:
    /// every failure path folds into `EmptyHookOutput`.
    static func handle(
        stdinJSON: Data,
        read: (_ consumerID: String, _ conversationID: String, _ workingRoot: String?, _ turnID: String?) -> [SelectionSnapshot],
        ack: (_ snapshotIDs: [SnapshotID], _ consumptionID: String) -> Void
    ) -> Data {
        guard let input = try? JSONDecoder().decode(PreInvocationInput.self, from: stdinJSON),
              let conversationID = nonEmpty(input.conversationId) else {
            return emptyOutput()
        }

        // The strongest identity available *before* reading: turn ID,
        // then prompt event ID. "Conversation plus Snapshot version" (the
        // weakest tier) can't be formed yet — it needs a Snapshot's
        // `version`, which only exists after `read` returns — so it is
        // computed below, only if needed, for `ack`'s consumptionID.
        let strongIdentity = nonEmpty(input.turnId) ?? nonEmpty(input.promptEventId)
        let documentedRoots = input.workspacePaths?.compactMap(nonEmpty) ?? []
        let legacyRoots = [input.cwd].compactMap { $0 }.compactMap(nonEmpty)
        let workingRoots = unique(documentedRoots.isEmpty ? legacyRoots : documentedRoots)
        guard !workingRoots.isEmpty else { return emptyOutput() }

        var seenSnapshotIDs = Set<SnapshotID>()
        var snapshots: [SelectionSnapshot] = []
        for workingRoot in workingRoots {
            for snapshot in read("antigravity", conversationID, workingRoot, strongIdentity)
                where !snapshot.isEffectivelyEmpty && seenSnapshotIDs.insert(snapshot.id).inserted {
                snapshots.append(snapshot)
            }
        }
        snapshots.sort {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.rawValue < $1.id.rawValue
        }

        guard !snapshots.isEmpty, let rendered = SelectionContextRenderer.render(snapshots) else {
            return emptyOutput()
        }

        let consumptionID = strongIdentity ?? conversationAndVersionIdentity(conversationID: conversationID, snapshots: snapshots)
        ack(snapshots.map(\.id), consumptionID)

        let output = HookOutputWithInjection(injectSteps: [InjectStep(ephemeralMessage: rendered)])
        return (try? JSONEncoder().encode(output)) ?? emptyOutput()
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    /// The last-resort Consumption identity: conversation plus Snapshot
    /// version. Several Snapshots (issue #8: several Armed Documents in
    /// scope) each carry their own `version`, so this joins every
    /// injected Snapshot's version rather than picking just one — still a
    /// single deterministic string per call.
    private static func conversationAndVersionIdentity(conversationID: String, snapshots: [SelectionSnapshot]) -> String {
        let versions = snapshots.map(\.version).sorted().map(String.init).joined(separator: ",")
        return "\(conversationID)#v\(versions)"
    }

    private static func emptyOutput() -> Data {
        (try? JSONEncoder().encode(EmptyHookOutput())) ?? Data("{}".utf8)
    }
}

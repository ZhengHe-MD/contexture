import BridgeClient
import ContextureKit
import Foundation

/// Antigravity's `PreInvocation` hook payload this adapter cares about.
///
/// Antigravity's exact stdin JSON schema is not confirmed by any source
/// available to this repo — docs/research/agent-compatibility.md's "Google
/// Antigravity" section (the authoritative spec for this repo, per issue
/// #11) describes `PreInvocation`'s *behavior* ("runs before each model
/// call", "may return `injectSteps`, including an `ephemeralMessage`") but
/// never its input field names. The names below are a documented,
/// best-effort guess — camelCase, mirroring the casing Antigravity's own
/// documented *output* vocabulary uses (`injectSteps`, `ephemeralMessage`)
/// rather than Claude Code's snake_case (`session_id`, `hook_event_name`).
///
/// - `turnId`: the strongest available host identity (docs/architecture/
///   selection-bridge.md "Lifecycle and deduplication" priority order). A
///   single user turn is expected to span several `PreInvocation` calls,
///   and this is the identity expected to stay stable across all of them.
/// - `promptEventId`: the fallback when `turnId` is absent — a per-hook-
///   invocation identity. Weaker than `turnId` because nothing in the
///   research doc confirms it is shared across every `PreInvocation` call
///   within one turn rather than being unique to each call.
/// - `conversationId`: the outermost, always-expected identity. Combined
///   with a Snapshot's own `version` as the last-resort Consumption key
///   (see `AntigravityAdapterCore.handle` below) when neither `turnId` nor
///   `promptEventId` is present.
/// - `cwd`: the Working Root equivalent, named to match Claude Code's own
///   stdin field (Sources/ClaudeCodeAdapter/AdapterCore.swift) since no
///   Antigravity-specific name is documented either.
struct PreInvocationInput: Decodable {
    let turnId: String?
    let promptEventId: String?
    let conversationId: String?
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

        let snapshots = read("antigravity", conversationID, input.cwd, strongIdentity)
            .filter { !$0.isEffectivelyEmpty }

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

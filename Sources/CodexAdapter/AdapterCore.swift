import BridgeClient
import ContextureKit
import Foundation

/// The Codex `UserPromptSubmit` hook payload this adapter cares about.
/// Source: docs/research/agent-compatibility.md "OpenAI Codex" — "Codex
/// hooks ... UserPromptSubmit receives the pending prompt and a Codex turn
/// ID. Plain stdout or hookSpecificOutput.additionalContext becomes extra
/// developer context." / https://learn.chatgpt.com/docs/hooks.
///
/// Field-name mapping: the research doc names the *event* (`UserPromptSubmit`)
/// and the *output* field (`hookSpecificOutput.additionalContext`) exactly,
/// and separately notes the hook shape is close to Claude Code's — but it
/// does not spell out the stdin JSON key names for the prompt, turn ID, or
/// working directory. Lacking a more concrete source, this adapter mirrors
/// Claude Code's own snake_case stdin convention (`session_id`, `cwd`) one
/// field at a time:
///   - `turn_id` for "a Codex turn ID" — same snake_case shape as Claude
///     Code's `session_id`, renamed for the identity Codex actually
///     documents (a turn, not a session).
///   - `cwd` — reused verbatim from Claude Code, since the adapter seam
///     needs *a* Working Root field from every host's hook payload
///     (docs/architecture/selection-bridge.md "Adapter seam", translation
///     1) and the doc gives no reason to expect Codex spells it
///     differently.
///   - `prompt` is present on real Codex stdin (the doc: "receives the
///     pending prompt") but, like Claude Code's adapter, is never decoded
///     here — this adapter only ever adds `additionalContext`, so it has no
///     use for the prompt text itself.
struct UserPromptSubmitInput: Decodable {
    let turnID: String?
    let cwd: String?

    enum CodingKeys: String, CodingKey {
        case turnID = "turn_id"
        case cwd
    }
}

struct HookSpecificOutput: Encodable {
    let hookEventName: String
    let additionalContext: String
}

struct HookOutput: Encodable {
    let hookSpecificOutput: HookSpecificOutput
}

/// The adapter's three translations (docs/architecture/selection-bridge.md
/// "Adapter seam"), as a pure function over injected read/ack so it's
/// testable without a real socket or process. The executable entry point
/// (AdapterMain.swift) supplies real stdin bytes and a real BridgeClient;
/// this never touches I/O directly.
enum CodexAdapterCore {
    /// Returns the exact bytes to write to stdout, or nil for "write
    /// nothing" — the research doc notes Codex, like Claude Code, "return[s]
    /// successful hook output without an additional-context field" to leave
    /// an ordinary prompt untouched, which is the required behavior for
    /// every no-context case (missing bridge, no selection, whitespace-only,
    /// decode failure, and so on). This function never throws: every
    /// failure path folds into the neutral nil result.
    ///
    /// Consumption identity: this ticket's explicit acceptance criterion is
    /// that the Codex turn ID is the Consumption identity. Codex's stronger
    /// identity is the turn ID itself (docs/research/agent-compatibility.md
    /// — Codex "supplies a turn ID"; no session-level id is documented at
    /// all), so — analogous to how the Claude Code adapter uses
    /// `session_id` for every identity role it needs — the turn ID fills
    /// every role here: it is passed as both `conversationID` and `turnID`
    /// to `read(...)`, and as the `ack` consumptionID.
    static func handle(
        stdinJSON: Data,
        read: (_ consumerID: String, _ conversationID: String, _ workingRoot: String?, _ turnID: String?) -> [SelectionSnapshot],
        ack: (_ snapshotIDs: [SnapshotID], _ consumptionID: String) -> Void
    ) -> Data? {
        guard let input = try? JSONDecoder().decode(UserPromptSubmitInput.self, from: stdinJSON),
              let turnID = input.turnID else {
            return nil
        }

        let snapshots = read("codex", turnID, input.cwd, turnID)
            .filter { !$0.isEffectivelyEmpty }

        guard !snapshots.isEmpty, let rendered = SelectionContextRenderer.render(snapshots) else {
            return nil
        }

        ack(snapshots.map(\.id), turnID)

        let output = HookOutput(
            hookSpecificOutput: HookSpecificOutput(hookEventName: "UserPromptSubmit", additionalContext: rendered)
        )
        return try? JSONEncoder().encode(output)
    }
}

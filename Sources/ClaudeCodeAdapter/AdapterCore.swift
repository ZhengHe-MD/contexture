import BridgeClient
import ContextureKit
import Foundation

/// The Claude Code `UserPromptSubmit` hook payload this adapter cares
/// about. Source: docs/research/agent-compatibility.md "Claude Code" /
/// https://code.claude.com/docs/en/hooks.
struct UserPromptSubmitInput: Decodable {
    let sessionID: String?
    let cwd: String?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
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
enum ClaudeCodeAdapterCore {
    /// Returns the exact bytes to write to stdout, or nil for "write
    /// nothing" — Claude Code treats an empty hook result as leaving the
    /// prompt untouched, which is the required behavior for every
    /// no-context case (missing bridge, no selection, whitespace-only,
    /// decode failure, and so on). This function never throws: every
    /// failure path folds into the neutral nil result.
    static func handle(
        stdinJSON: Data,
        read: (_ consumerID: String, _ conversationID: String, _ workingRoot: String?, _ turnID: String?) -> [SelectionSnapshot],
        ack: (_ snapshotIDs: [SnapshotID], _ consumptionID: String) -> Void
    ) -> Data? {
        guard let input = try? JSONDecoder().decode(UserPromptSubmitInput.self, from: stdinJSON),
              let sessionID = input.sessionID else {
            return nil
        }

        let snapshots = read("claude-code", sessionID, input.cwd, sessionID)
            .filter { !$0.isEffectivelyEmpty }

        guard !snapshots.isEmpty, let rendered = SelectionContextRenderer.render(snapshots) else {
            return nil
        }

        ack(snapshots.map(\.id), sessionID)

        let output = HookOutput(
            hookSpecificOutput: HookSpecificOutput(hookEventName: "UserPromptSubmit", additionalContext: rendered)
        )
        return try? JSONEncoder().encode(output)
    }
}

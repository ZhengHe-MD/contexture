import ConformanceHarness
import Foundation

/// Wraps the real, compiled `CodexAdapter` executable as a black-box
/// `AdapterUnderTest` — the harness (issue #9) only ever talks to it as a
/// genuine subprocess through stdin/stdout, the same way Codex itself would
/// invoke it as a `UserPromptSubmit` hook.
///
/// Only `turn_id`, `cwd`, and `prompt` are sent — `HarnessScenario.conversationID`
/// has no Codex counterpart (see AdapterCore.swift's field-name-mapping
/// comment: Codex documents a turn ID only, no separate session-level id),
/// so it is intentionally not forwarded here.
struct CodexAdapterUnderTest: AdapterUnderTest {
    let name = "Codex"
    let executableURL: URL

    func invoke(scenario: HarnessScenario, bridgeSocketPath: String) throws -> HookResult {
        let stdinObject: [String: Any] = [
            "turn_id": scenario.turnID,
            "cwd": scenario.workingRoot,
            "hook_event_name": "UserPromptSubmit",
            "prompt": scenario.prompt,
        ]
        let stdinData = try JSONSerialization.data(withJSONObject: stdinObject)

        let process = Process()
        process.executableURL = executableURL
        process.environment = ["CONTEXTURE_BRIDGE_SOCKET": bridgeSocketPath]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()

        try process.run()
        stdinPipe.fileHandleForWriting.write(stdinData)
        try stdinPipe.fileHandleForWriting.close()
        let output = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        var injectedContext: String?
        if !output.isEmpty,
           let json = try? JSONSerialization.jsonObject(with: output) as? [String: Any],
           let hookSpecificOutput = json["hookSpecificOutput"] as? [String: Any] {
            injectedContext = hookSpecificOutput["additionalContext"] as? String
        }
        return HookResult(injectedContext: injectedContext, rawStdout: output)
    }
}

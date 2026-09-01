import ConformanceHarness
import Foundation

/// Wraps the real, compiled `ClaudeCodeAdapter` executable as a black-box
/// `AdapterUnderTest` — the harness (issue #9) only ever talks to it as a
/// genuine subprocess through stdin/stdout, the same way Claude Code itself
/// would invoke it as a `UserPromptSubmit` hook.
struct ClaudeCodeAdapterUnderTest: AdapterUnderTest {
    let name = "Claude Code"
    let executableURL: URL

    func invoke(scenario: HarnessScenario, bridgeSocketPath: String) throws -> HookResult {
        let stdinObject: [String: Any] = [
            "session_id": scenario.conversationID,
            "cwd": scenario.workingRoot,
            "hook_event_name": "UserPromptSubmit",
            "prompt": scenario.prompt,
        ]
        let stdinData = try JSONSerialization.data(withJSONObject: stdinObject)

        let process = Process()
        process.executableURL = executableURL
        // Also redirects the content-free diagnostics log (issue #12) to a
        // scratch path alongside the throwaway socket, so a harness run
        // never writes into the real per-user log.
        process.environment = [
            "CONTEXTURE_BRIDGE_SOCKET": bridgeSocketPath,
            "CONTEXTURE_DIAGNOSTICS_LOG_PATH": bridgeSocketPath + ".diagnostics.log",
        ]

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

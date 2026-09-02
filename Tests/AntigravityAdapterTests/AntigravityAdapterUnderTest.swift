import ConformanceHarness
import Foundation

/// Wraps the real, compiled `AntigravityAdapter` executable as a black-box
/// `AdapterUnderTest` — the harness (issue #9) only ever talks to it as a
/// genuine subprocess through stdin/stdout, the same way Antigravity itself
/// would invoke it as a `PreInvocation` hook.
struct AntigravityAdapterUnderTest: AdapterUnderTest {
    let name = "Antigravity"
    let executableURL: URL

    func invoke(scenario: HarnessScenario, bridgeSocketPath: String) throws -> HookResult {
        // Match Antigravity 2.11's documented PreInvocation input shape.
        // Antigravity does not expose a per-turn ID here; the Bridge's
        // successful Next Prompt acknowledgement prevents repeat injection.
        let stdinObject: [String: Any] = [
            "invocationNum": 0,
            "initialNumSteps": 0,
            "conversationId": scenario.conversationID,
            "workspacePaths": [scenario.workingRoot],
            "transcriptPath": "/tmp/contexture-antigravity-transcript.jsonl",
            "artifactDirectoryPath": "/tmp/contexture-antigravity-artifacts",
            "modelName": "test-model",
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
           let injectSteps = json["injectSteps"] as? [[String: Any]],
           let first = injectSteps.first {
            injectedContext = first["ephemeralMessage"] as? String
        }
        return HookResult(injectedContext: injectedContext, rawStdout: output)
    }
}

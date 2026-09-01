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
        // Field names match PreInvocationInput (Sources/AntigravityAdapter/
        // AdapterCore.swift) — a documented best-effort guess at
        // Antigravity's real `PreInvocation` stdin shape. `turnId` carries
        // the harness's turn identity directly; there is no separate
        // prompt-event identity in `HarnessScenario`; a real host might
        // supply one alongside `turnId`, but the harness never needs the
        // fallback path exercised through this wrapper since `turnId` is
        // always present here.
        let stdinObject: [String: Any] = [
            "hookEventName": "PreInvocation",
            "turnId": scenario.turnID,
            "conversationId": scenario.conversationID,
            "cwd": scenario.workingRoot,
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
           let injectSteps = json["injectSteps"] as? [[String: Any]],
           let first = injectSteps.first {
            injectedContext = first["ephemeralMessage"] as? String
        }
        return HookResult(injectedContext: injectedContext, rawStdout: output)
    }
}

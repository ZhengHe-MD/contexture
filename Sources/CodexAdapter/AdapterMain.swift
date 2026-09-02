import BridgeClient
import ContextureKit
import Foundation

// `@main` rather than a `main.swift` script — see ContextureApp/AppMain.swift
// and ClaudeCodeAdapter/AdapterMain.swift for why: it keeps this target
// testable via `@testable import` without a script-mode main executing (and
// here, blocking on a real stdin read) the moment the test binary starts.
@main
enum CodexAdapterMain {
    static func main() {
        let stdinData = FileHandle.standardInput.readDataToEndOfFile()
        // Overridable so the shared black-box conformance harness (issue
        // #9) can point a real, unmodified copy of this executable at a
        // throwaway Bridge instead of the real per-user one. Absent in
        // every real installation, where the default applies as always.
        let socketPath = ProcessInfo.processInfo.environment["CONTEXTURE_BRIDGE_SOCKET"]
            ?? BridgeLocation.defaultSocketPath()
        let client = BridgeClient(socketPath: socketPath)

        // Set only inside the `ack` closure below, which AdapterCore calls
        // only on the has-content path — see ClaudeCodeAdapter/AdapterMain.swift
        // for why this is how the count reaches the diagnostics log.
        var injectedSnapshotCount: Int?

        let output = CodexAdapterCore.handle(
            stdinJSON: stdinData,
            read: { consumerID, conversationID, workingRoot, turnID in
                client.read(consumerID: consumerID, conversationID: conversationID, workingRoot: workingRoot, turnID: turnID)
            },
            ack: { snapshotIDs, consumptionID in
                injectedSnapshotCount = snapshotIDs.count
                client.ack(snapshotIDs: snapshotIDs, consumptionID: consumptionID)
            }
        )

        // Same override rationale as CONTEXTURE_BRIDGE_SOCKET above — lets
        // the conformance harness (and any other test) keep every real
        // subprocess invocation it makes out of the real per-user log.
        let diagnosticsLogPath = ProcessInfo.processInfo.environment["CONTEXTURE_DIAGNOSTICS_LOG_PATH"]
            ?? AdapterDiagnosticsLog.defaultPath()
        AdapterDiagnosticsLog.record(
            AdapterDiagnosticEntry(
                timestamp: Date(),
                adapterID: "codex",
                outcome: injectedSnapshotCount != nil ? .injected : .noInjection,
                injectedSnapshotCount: injectedSnapshotCount
            ),
            path: diagnosticsLogPath
        )

        if let output {
            FileHandle.standardOutput.write(output)
        }
        exit(0)
    }
}

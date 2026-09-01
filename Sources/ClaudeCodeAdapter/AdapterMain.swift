import BridgeClient
import Foundation

// `@main` rather than a `main.swift` script — see ContextureApp/AppMain.swift
// for why: it keeps this target testable via `@testable import` without a
// script-mode main executing (and here, blocking on a real stdin read)
// the moment the test binary starts.
@main
enum ClaudeCodeAdapterMain {
    static func main() {
        let stdinData = FileHandle.standardInput.readDataToEndOfFile()
        let client = BridgeClient()

        let output = ClaudeCodeAdapterCore.handle(
            stdinJSON: stdinData,
            read: { consumerID, conversationID, workingRoot, turnID in
                client.read(consumerID: consumerID, conversationID: conversationID, workingRoot: workingRoot, turnID: turnID)
            },
            ack: { snapshotIDs, consumptionID in
                client.ack(snapshotIDs: snapshotIDs, consumptionID: consumptionID)
            }
        )

        if let output {
            FileHandle.standardOutput.write(output)
        }
        exit(0)
    }
}

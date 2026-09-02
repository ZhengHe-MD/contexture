import BridgeClient
import ContextureKit
import Foundation
import Testing
@testable import CodexAdapter

@Suite struct CodexAdapterCoreTests {
    private func snapshot(text: String) -> SelectionSnapshot {
        let data = Data(text.utf8)
        return SelectionSnapshot(
            documentID: DocumentID(),
            sourceBytes: data,
            format: .markdown,
            relativePath: "notes.md",
            absolutePath: "/tmp/notes.md",
            revision: RevisionHash(contentBytes: data),
            byteRange: SourceByteRange(lowerBound: 0, upperBound: data.count),
            sharingMode: .nextPrompt,
            createdAt: Date(),
            sourceWindow: SourceWindowID(),
            version: 1
        )
    }

    private func stdin(turnID: String? = "turn-123", cwd: String? = "/Users/writer/project") -> Data {
        var object: [String: Any] = [:]
        if let turnID { object["turn_id"] = turnID }
        if let cwd { object["cwd"] = cwd }
        object["hook_event_name"] = "UserPromptSubmit"
        object["prompt"] = "what does this mean?"
        return try! JSONSerialization.data(withJSONObject: object)
    }

    @Test func aValidSelectionProducesAdditionalContextAndAcksIt() throws {
        let snap = snapshot(text: "selected passage")
        var ackedIDs: [SnapshotID] = []
        var ackedConsumptionID: String?

        let output = CodexAdapterCore.handle(
            stdinJSON: stdin(),
            read: { consumerID, conversationID, workingRoot, turnID in
                #expect(consumerID == "codex")
                #expect(conversationID == "turn-123")
                #expect(workingRoot == "/Users/writer/project")
                #expect(turnID == "turn-123")
                return [snap]
            },
            ack: { ids, consumptionID in
                ackedIDs = ids
                ackedConsumptionID = consumptionID
            }
        )

        let data = try #require(output)
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let hookSpecificOutput = decoded?["hookSpecificOutput"] as? [String: Any]
        #expect(hookSpecificOutput?["hookEventName"] as? String == "UserPromptSubmit")
        let additionalContext = hookSpecificOutput?["additionalContext"] as? String
        #expect(additionalContext?.contains("selected passage") == true)
        #expect(additionalContext?.contains("Contexture Selection Context") == true)

        #expect(ackedIDs == [snap.id])
        // The Codex turn ID is the Consumption identity (issue #10's
        // explicit acceptance criterion) — it fills both the read()
        // conversationID/turnID roles and the ack consumptionID role, the
        // way Claude Code's session_id fills every identity role today.
        #expect(ackedConsumptionID == "turn-123")
    }

    @Test func noArmedSnapshotsProducesNilOutputAndNoAck() {
        var ackCalled = false
        let output = CodexAdapterCore.handle(
            stdinJSON: stdin(),
            read: { _, _, _, _ in [] },
            ack: { _, _ in ackCalled = true }
        )
        #expect(output == nil)
        #expect(!ackCalled)
    }

    @Test func whitespaceOnlySnapshotsAreFilteredOutEvenIfTheBridgeReturnsThem() {
        let whitespaceOnly = snapshot(text: "   \n\t  ")
        let output = CodexAdapterCore.handle(
            stdinJSON: stdin(),
            read: { _, _, _, _ in [whitespaceOnly] },
            ack: { _, _ in Issue.record("must not ack a snapshot that was never injected") }
        )
        #expect(output == nil)
    }

    @Test func missingTurnIDProducesNilOutputWithoutCallingBridge() {
        var bridgeCalled = false
        let output = CodexAdapterCore.handle(
            stdinJSON: stdin(turnID: nil),
            read: { _, _, _, _ in
                bridgeCalled = true
                return []
            },
            ack: { _, _ in }
        )
        #expect(output == nil)
        #expect(!bridgeCalled)
    }

    @Test func malformedStdinProducesNilOutputWithoutCallingBridge() {
        var bridgeCalled = false
        let output = CodexAdapterCore.handle(
            stdinJSON: Data("not json".utf8),
            read: { _, _, _, _ in
                bridgeCalled = true
                return []
            },
            ack: { _, _ in }
        )
        #expect(output == nil)
        #expect(!bridgeCalled)
    }

    @Test func emptyStdinProducesNilOutput() {
        let output = CodexAdapterCore.handle(
            stdinJSON: Data(),
            read: { _, _, _, _ in [] },
            ack: { _, _ in }
        )
        #expect(output == nil)
    }
}

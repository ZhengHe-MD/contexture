import BridgeClient
import ContextureKit
import Foundation
import Testing
@testable import ClaudeCodeAdapter

@Suite struct ClaudeCodeAdapterCoreTests {
    private func snapshot(text: String) -> SelectionSnapshot {
        let data = Data(text.utf8)
        return SelectionSnapshot(
            documentID: DocumentID(),
            sourceBytes: data,
            format: .markdown,
            relativePath: "notes.md",
            revision: RevisionHash(contentBytes: data),
            byteRange: SourceByteRange(lowerBound: 0, upperBound: data.count),
            sharingMode: .nextPrompt,
            createdAt: Date(),
            sourceWindow: SourceWindowID(),
            version: 1
        )
    }

    private func stdin(sessionID: String? = "session-123", cwd: String? = "/Users/writer/project") -> Data {
        var object: [String: Any] = [:]
        if let sessionID { object["session_id"] = sessionID }
        if let cwd { object["cwd"] = cwd }
        object["hook_event_name"] = "UserPromptSubmit"
        object["prompt"] = "what does this mean?"
        return try! JSONSerialization.data(withJSONObject: object)
    }

    @Test func aValidSelectionProducesAdditionalContextAndAcksIt() throws {
        let snap = snapshot(text: "selected passage")
        var ackedIDs: [SnapshotID] = []
        var ackedConsumptionID: String?

        let output = ClaudeCodeAdapterCore.handle(
            stdinJSON: stdin(),
            read: { consumerID, conversationID, workingRoot, turnID in
                #expect(consumerID == "claude-code")
                #expect(conversationID == "session-123")
                #expect(workingRoot == "/Users/writer/project")
                #expect(turnID == "session-123")
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
        #expect(ackedConsumptionID == "session-123")
    }

    @Test func noArmedSnapshotsProducesNilOutputAndNoAck() {
        var ackCalled = false
        let output = ClaudeCodeAdapterCore.handle(
            stdinJSON: stdin(),
            read: { _, _, _, _ in [] },
            ack: { _, _ in ackCalled = true }
        )
        #expect(output == nil)
        #expect(!ackCalled)
    }

    @Test func whitespaceOnlySnapshotsAreFilteredOutEvenIfTheBridgeReturnsThem() {
        let whitespaceOnly = snapshot(text: "   \n\t  ")
        let output = ClaudeCodeAdapterCore.handle(
            stdinJSON: stdin(),
            read: { _, _, _, _ in [whitespaceOnly] },
            ack: { _, _ in Issue.record("must not ack a snapshot that was never injected") }
        )
        #expect(output == nil)
    }

    @Test func missingSessionIDProducesNilOutputWithoutCallingBridge() {
        var bridgeCalled = false
        let output = ClaudeCodeAdapterCore.handle(
            stdinJSON: stdin(sessionID: nil),
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
        let output = ClaudeCodeAdapterCore.handle(
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
        let output = ClaudeCodeAdapterCore.handle(
            stdinJSON: Data(),
            read: { _, _, _, _ in [] },
            ack: { _, _ in }
        )
        #expect(output == nil)
    }
}

import BridgeClient
import ContextureKit
import Foundation
import Testing
@testable import AntigravityAdapter

@Suite struct AntigravityAdapterCoreTests {
    private func snapshot(text: String, version: Int = 1) -> SelectionSnapshot {
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
            version: version
        )
    }

    private func stdin(
        turnId: String? = "turn-123",
        promptEventId: String? = "event-456",
        conversationId: String? = "conv-789",
        cwd: String? = "/Users/writer/project"
    ) -> Data {
        var object: [String: Any] = [:]
        if let turnId { object["turnId"] = turnId }
        if let promptEventId { object["promptEventId"] = promptEventId }
        if let conversationId { object["conversationId"] = conversationId }
        if let cwd { object["cwd"] = cwd }
        object["hookEventName"] = "PreInvocation"
        return try! JSONSerialization.data(withJSONObject: object)
    }

    /// Parses raw output bytes and asserts the `injectSteps` key is
    /// literally absent — not merely decoded to `nil` by a Swift
    /// `Decodable` type that would treat "absent" and "present but empty"
    /// the same way. Point 3 of the ticket's brief calls this out
    /// explicitly: the harness's generic "no Contexture content" string
    /// check doesn't distinguish `{}` from `{"injectSteps": []}` or
    /// `{"injectSteps": null}`, so this test must.
    private func assertInjectStepsKeyAbsent(_ data: Data, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any], sourceLocation: sourceLocation)
        #expect(json.index(forKey: "injectSteps") == nil, "expected the injectSteps key to be entirely absent, got: \(json)", sourceLocation: sourceLocation)
    }

    // MARK: Has-content shape

    @Test func aValidSelectionProducesInjectStepsWithAnEphemeralMessageAndAcksIt() throws {
        let snap = snapshot(text: "selected passage")
        var ackedIDs: [SnapshotID] = []
        var ackedConsumptionID: String?

        let output = AntigravityAdapterCore.handle(
            stdinJSON: stdin(),
            read: { consumerID, conversationID, workingRoot, turnID in
                #expect(consumerID == "antigravity")
                #expect(conversationID == "conv-789")
                #expect(workingRoot == "/Users/writer/project")
                #expect(turnID == "turn-123")
                return [snap]
            },
            ack: { ids, consumptionID in
                ackedIDs = ids
                ackedConsumptionID = consumptionID
            }
        )

        let decoded = try #require(try JSONSerialization.jsonObject(with: output) as? [String: Any])
        let injectSteps = try #require(decoded["injectSteps"] as? [[String: Any]])
        #expect(injectSteps.count == 1)
        let ephemeralMessage = injectSteps.first?["ephemeralMessage"] as? String
        #expect(ephemeralMessage?.contains("selected passage") == true)
        #expect(ephemeralMessage?.contains("Contexture Selection Context") == true)

        #expect(ackedIDs == [snap.id])
        // Strongest identity (turnId) wins as the Consumption key.
        #expect(ackedConsumptionID == "turn-123")
    }

    // MARK: No-content shape — must be `{}`, not "write nothing"

    @Test func noArmedSnapshotsProducesAnEmptyObjectWithInjectStepsAbsentAndNoAck() throws {
        var ackCalled = false
        let output = AntigravityAdapterCore.handle(
            stdinJSON: stdin(),
            read: { _, _, _, _ in [] },
            ack: { _, _ in ackCalled = true }
        )
        #expect(!ackCalled)
        try assertInjectStepsKeyAbsent(output)
        // The exact neutral shape per docs/research/agent-compatibility.md
        // "Neutral output is supported": an empty JSON object.
        #expect(String(decoding: output, as: UTF8.self) == "{}")
    }

    @Test func whitespaceOnlySnapshotsAreFilteredOutEvenIfTheBridgeReturnsThem() throws {
        let whitespaceOnly = snapshot(text: "   \n\t  ")
        let output = AntigravityAdapterCore.handle(
            stdinJSON: stdin(),
            read: { _, _, _, _ in [whitespaceOnly] },
            ack: { _, _ in Issue.record("must not ack a snapshot that was never injected") }
        )
        try assertInjectStepsKeyAbsent(output)
    }

    @Test func missingConversationIdProducesAnEmptyObjectWithoutCallingBridge() throws {
        var bridgeCalled = false
        let output = AntigravityAdapterCore.handle(
            stdinJSON: stdin(conversationId: nil),
            read: { _, _, _, _ in
                bridgeCalled = true
                return []
            },
            ack: { _, _ in }
        )
        #expect(!bridgeCalled)
        try assertInjectStepsKeyAbsent(output)
    }

    @Test func malformedStdinProducesAnEmptyObjectWithoutCallingBridge() throws {
        var bridgeCalled = false
        let output = AntigravityAdapterCore.handle(
            stdinJSON: Data("not json".utf8),
            read: { _, _, _, _ in
                bridgeCalled = true
                return []
            },
            ack: { _, _ in }
        )
        #expect(!bridgeCalled)
        try assertInjectStepsKeyAbsent(output)
    }

    @Test func emptyStdinProducesAnEmptyObject() throws {
        let output = AntigravityAdapterCore.handle(
            stdinJSON: Data(),
            read: { _, _, _, _ in [] },
            ack: { _, _ in }
        )
        try assertInjectStepsKeyAbsent(output)
    }

    // MARK: Consumption-keying priority order

    @Test func turnIdIsPreferredOverPromptEventIdAndConversationId() {
        var readWasCalled = false
        var capturedTurnID: String?
        let output = AntigravityAdapterCore.handle(
            stdinJSON: stdin(turnId: "turn-1", promptEventId: "event-1", conversationId: "conv-1"),
            read: { _, _, _, turnID in
                readWasCalled = true
                capturedTurnID = turnID
                return [snapshot(text: "content")]
            },
            ack: { _, consumptionID in
                #expect(consumptionID == "turn-1")
            }
        )
        #expect(readWasCalled)
        #expect(capturedTurnID == "turn-1")
        #expect(output.count > 2) // not the bare `{}`
    }

    @Test func promptEventIdIsUsedWhenTurnIdIsAbsent() {
        var readWasCalled = false
        var capturedTurnID: String?
        let output = AntigravityAdapterCore.handle(
            stdinJSON: stdin(turnId: nil, promptEventId: "event-1", conversationId: "conv-1"),
            read: { _, _, _, turnID in
                readWasCalled = true
                capturedTurnID = turnID
                return [snapshot(text: "content")]
            },
            ack: { _, consumptionID in
                #expect(consumptionID == "event-1")
            }
        )
        #expect(readWasCalled)
        #expect(capturedTurnID == "event-1")
        #expect(output.count > 2)
    }

    @Test func conversationAndSnapshotVersionIsTheLastResortWhenNeitherTurnIdNorPromptEventIdIsPresent() {
        var readWasCalled = false
        var capturedTurnID: String?
        let output = AntigravityAdapterCore.handle(
            stdinJSON: stdin(turnId: nil, promptEventId: nil, conversationId: "conv-1"),
            read: { _, _, _, turnID in
                readWasCalled = true
                capturedTurnID = turnID
                return [snapshot(text: "content", version: 3)]
            },
            ack: { _, consumptionID in
                #expect(consumptionID == "conv-1#v3")
            }
        )
        #expect(readWasCalled)
        // No stronger identity was available to pass to `read` either —
        // this is a nil turnID, not a synthesized one, since the
        // synthesized identity needs a Snapshot's version, which doesn't
        // exist until after `read` returns.
        #expect(capturedTurnID == nil)
        #expect(output.count > 2)
    }

    @Test func emptyStringIdentitiesAreTreatedAsAbsent() {
        // Defensive: a host sending `""` rather than omitting the field
        // must not be treated as a present, stronger identity than it is.
        var capturedTurnID: String?
        _ = AntigravityAdapterCore.handle(
            stdinJSON: stdin(turnId: "", promptEventId: "event-1", conversationId: "conv-1"),
            read: { _, _, _, turnID in
                capturedTurnID = turnID
                return [snapshot(text: "content")]
            },
            ack: { _, _ in }
        )
        #expect(capturedTurnID == "event-1")
    }
}

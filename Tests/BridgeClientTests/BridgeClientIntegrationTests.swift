import BridgeClient
import ContextureKit
import Foundation
import SelectionBridge
import Testing

/// End-to-end over the real transport: a live SelectionBridgeServer on a
/// temporary Unix domain socket, exercised by a real BridgeClient — the
/// same HTTP-over-UDS wire an Agent Adapter process actually uses. This is
/// the one place both sides of the protocol are proven compatible.
///
/// Every snapshot here lives under `/tmp`, and every `read()` call passes
/// `workingRoot: "/tmp"` to match — issue #8 made an absent/unmatched
/// Working Root return `[]` unconditionally (docs/adr/0004), so a `nil`
/// workingRoot here would silently test nothing.
@Suite struct BridgeClientIntegrationTests {
    private func temporarySocketPath() -> String {
        // sockaddr_un.sun_path is a hard 104-byte kernel limit on macOS —
        // FileManager.default.temporaryDirectory (a long per-process
        // /var/folders/.../T/ path) plus a full UUID reliably exceeds it,
        // so this uses /tmp directly with a short random suffix instead.
        "/tmp/ctx-\(UUID().uuidString.prefix(8)).sock"
    }

    private func snapshot(text: String = "selected text", documentID: DocumentID = DocumentID()) -> SelectionSnapshot {
        let data = Data(text.utf8)
        return SelectionSnapshot(
            documentID: documentID,
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

    @Test func readReturnsAPublishedSnapshotOverTheRealSocket() throws {
        let path = temporarySocketPath()
        let server = SelectionBridgeServer(socketPath: path)
        try server.start()
        defer { server.stop() }

        let snap = snapshot(text: "selected text")
        server.publish(snap)

        let client = BridgeClient(socketPath: path, timeout: 2)
        let results = client.read(consumerID: "test", conversationID: "conv-1", workingRoot: "/tmp", turnID: nil)

        #expect(results.count == 1)
        #expect(results.first?.id == snap.id)
        #expect(results.first.map { String(decoding: $0.sourceBytes, as: UTF8.self) } == "selected text")
    }

    @Test func ackRemovesTheSnapshotSoALaterReadReturnsNothing() throws {
        let path = temporarySocketPath()
        let server = SelectionBridgeServer(socketPath: path)
        try server.start()
        defer { server.stop() }

        let snap = snapshot()
        server.publish(snap)

        let client = BridgeClient(socketPath: path, timeout: 2)
        let first = client.read(consumerID: "test", conversationID: "conv-1", workingRoot: "/tmp", turnID: nil)
        #expect(first.count == 1)

        client.ack(snapshotIDs: [snap.id], consumptionID: "conv-1")

        let second = client.read(consumerID: "test", conversationID: "conv-1", workingRoot: "/tmp", turnID: nil)
        #expect(second.isEmpty)
    }

    @Test func readReturnsEmptyWhenTheBridgeIsAbsent() {
        let client = BridgeClient(socketPath: temporarySocketPath(), timeout: 0.5)
        let results = client.read(consumerID: "test", conversationID: "conv-1", workingRoot: "/tmp", turnID: nil)
        #expect(results.isEmpty)
    }

    @Test func ackAgainstAnAbsentBridgeDoesNotThrowOrHang() {
        let client = BridgeClient(socketPath: temporarySocketPath(), timeout: 0.5)
        client.ack(snapshotIDs: [SnapshotID()], consumptionID: "conv-1")
    }

    @Test func ackOverTheRealSocketFiresTheServersArmedChangeObserver() throws {
        // ack is only ever invoked over the real socket by an Adapter
        // process — the app's in-process passthroughs never call it — so
        // this is the one Armed-change-observer path that must be proven
        // through the real HTTP-over-UDS transport rather than a direct
        // SelectionBridgeServer method call.
        let path = temporarySocketPath()
        let server = SelectionBridgeServer(socketPath: path)
        try server.start()
        defer { server.stop() }

        let snap = snapshot()
        server.publish(snap)

        var fireCount = 0
        server.addArmedChangeObserver { fireCount += 1 }

        let client = BridgeClient(socketPath: path, timeout: 2)
        client.ack(snapshotIDs: [snap.id], consumptionID: "conv-1")

        #expect(fireCount == 1)
    }

    @Test func severalArmedDocumentsAllArriveOrderedMostRecentFirst() throws {
        let path = temporarySocketPath()
        let server = SelectionBridgeServer(socketPath: path)
        try server.start()
        defer { server.stop() }

        let first = snapshot(text: "first doc")
        server.publish(first)
        // Ensure a distinguishable ordering key even at coarse clock
        // resolution — the store sorts by createdAt.
        let second = SelectionSnapshot(
            documentID: DocumentID(),
            sourceBytes: Data("second doc".utf8),
            format: .markdown,
            relativePath: "second.md",
            absolutePath: "/tmp/second.md",
            revision: RevisionHash(contentBytes: Data("second doc".utf8)),
            byteRange: SourceByteRange(lowerBound: 0, upperBound: Data("second doc".utf8).count),
            sharingMode: .nextPrompt,
            createdAt: first.createdAt.addingTimeInterval(10),
            sourceWindow: SourceWindowID(),
            version: 1
        )
        server.publish(second)

        let client = BridgeClient(socketPath: path, timeout: 2)
        let results = client.read(consumerID: "test", conversationID: "conv-1", workingRoot: "/tmp", turnID: nil)
        #expect(results.map(\.id) == [second.id, first.id])
    }

    @Test func aDocumentOutsideTheWorkingRootNeverArrives() throws {
        let path = temporarySocketPath()
        let server = SelectionBridgeServer(socketPath: path)
        try server.start()
        defer { server.stop() }

        let outside = SelectionSnapshot(
            documentID: DocumentID(),
            sourceBytes: Data("outside".utf8),
            format: .markdown,
            relativePath: "outside.md",
            absolutePath: "/Users/writer/other-project/outside.md",
            revision: RevisionHash(contentBytes: Data("outside".utf8)),
            byteRange: SourceByteRange(lowerBound: 0, upperBound: 7),
            sharingMode: .nextPrompt,
            createdAt: Date(),
            sourceWindow: SourceWindowID(),
            version: 1
        )
        server.publish(outside)

        let client = BridgeClient(socketPath: path, timeout: 2)
        let results = client.read(consumerID: "test", conversationID: "conv-1", workingRoot: "/Users/writer/project", turnID: nil)
        #expect(results.isEmpty)
    }

    @Test func aMissingWorkingRootReturnsNothingRatherThanEverything() throws {
        let path = temporarySocketPath()
        let server = SelectionBridgeServer(socketPath: path)
        try server.start()
        defer { server.stop() }

        server.publish(snapshot())

        let client = BridgeClient(socketPath: path, timeout: 2)
        let results = client.read(consumerID: "test", conversationID: "conv-1", workingRoot: nil, turnID: nil)
        #expect(results.isEmpty)
    }
}

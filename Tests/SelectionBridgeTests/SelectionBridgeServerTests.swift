import ContextureKit
import Foundation
import Testing
@testable import SelectionBridge

@Suite struct SelectionBridgeServerTests {
    private func temporarySocketPath() -> String {
        // sockaddr_un.sun_path is a hard 104-byte kernel limit on macOS —
        // FileManager.default.temporaryDirectory (a long per-process
        // /var/folders/.../T/ path) plus a full UUID reliably exceeds it,
        // so this uses /tmp directly with a short random suffix instead.
        "/tmp/ctx-\(UUID().uuidString.prefix(8)).sock"
    }

    private func snapshot(documentID: DocumentID, text: String = "hello world", version: Int = 1) -> SelectionSnapshot {
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
            version: version
        )
    }

    @Test func socketIsCreatedAtUserOnlyPermissions() throws {
        let path = temporarySocketPath()
        let server = SelectionBridgeServer(socketPath: path)
        try server.start()
        defer { server.stop() }

        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let permissions = attributes[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
    }

    @Test func stopRemovesTheSocketFile() throws {
        let path = temporarySocketPath()
        let server = SelectionBridgeServer(socketPath: path)
        try server.start()
        #expect(FileManager.default.fileExists(atPath: path))
        server.stop()
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test func startingTwiceAtTheSamePathDoesNotThrow() throws {
        // A stale socket file left over from a crashed previous run must
        // not block a fresh start.
        let path = temporarySocketPath()
        let first = SelectionBridgeServer(socketPath: path)
        try first.start()
        first.stop()

        let second = SelectionBridgeServer(socketPath: path)
        try second.start()
        defer { second.stop() }
        #expect(FileManager.default.fileExists(atPath: path))
    }

    @Test func isArmedReflectsWhatWasPublishedForThatDocument() {
        let server = SelectionBridgeServer(store: SelectionStore())
        let documentID = DocumentID()
        #expect(!server.isArmed(documentID: documentID))
        server.publish(snapshot(documentID: documentID))
        #expect(server.isArmed(documentID: documentID))
    }

    @Test func isArmedIsFalseForAnUnrelatedDocument() {
        let server = SelectionBridgeServer(store: SelectionStore())
        server.publish(snapshot(documentID: DocumentID()))
        #expect(!server.isArmed(documentID: DocumentID()))
    }

    @Test func isArmedIsFalseAfterClear() {
        let server = SelectionBridgeServer(store: SelectionStore())
        let documentID = DocumentID()
        server.publish(snapshot(documentID: documentID))
        server.clear(documentID: documentID)
        #expect(!server.isArmed(documentID: documentID))
    }

    @Test func isArmedIsFalseForAWhitespaceOnlySnapshot() {
        // Matches read()'s own filtering — an indicator built on isArmed
        // must not claim something is Armed that could never be injected.
        let server = SelectionBridgeServer(store: SelectionStore())
        let documentID = DocumentID()
        server.publish(snapshot(documentID: documentID, text: "   \n\t "))
        #expect(!server.isArmed(documentID: documentID))
    }

    @Test func armedChangeObserverFiresOnPublish() {
        let server = SelectionBridgeServer(store: SelectionStore())
        var fireCount = 0
        server.addArmedChangeObserver { fireCount += 1 }
        server.publish(snapshot(documentID: DocumentID()))
        #expect(fireCount == 1)
    }

    @Test func armedChangeObserverFiresOnClear() {
        let server = SelectionBridgeServer(store: SelectionStore())
        let documentID = DocumentID()
        server.publish(snapshot(documentID: documentID))
        var fireCount = 0
        server.addArmedChangeObserver { fireCount += 1 }
        server.clear(documentID: documentID)
        #expect(fireCount == 1)
    }

    @Test func removedArmedChangeObserverDoesNotFireAgain() {
        let server = SelectionBridgeServer(store: SelectionStore())
        var fireCount = 0
        let token = server.addArmedChangeObserver { fireCount += 1 }
        server.removeArmedChangeObserver(token)
        server.publish(snapshot(documentID: DocumentID()))
        #expect(fireCount == 0)
    }

    @Test func severalObserversAllFire() {
        // Several windows/Documents can be open at once, each with its own
        // Armed indicator watching the one shared Bridge.
        let server = SelectionBridgeServer(store: SelectionStore())
        var firstCount = 0
        var secondCount = 0
        server.addArmedChangeObserver { firstCount += 1 }
        server.addArmedChangeObserver { secondCount += 1 }
        server.publish(snapshot(documentID: DocumentID()))
        #expect(firstCount == 1)
        #expect(secondCount == 1)
    }

}

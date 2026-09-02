import ContextureKit
import Foundation
import Testing
@testable import SelectionBridge

@Suite struct SelectionStoreTests {
    private func snapshot(
        documentID: DocumentID = DocumentID(),
        text: String = "hello world",
        version: Int = 1,
        createdAt: Date = Date()
    ) -> SelectionSnapshot {
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
            createdAt: createdAt,
            sourceWindow: SourceWindowID(),
            version: version
        )
    }

    @Test func readReturnsWhatWasPublished() {
        let store = SelectionStore()
        let snap = snapshot()
        store.publish(snap)
        #expect(store.read().map(\.id) == [snap.id])
    }

    @Test func readOmitsWhitespaceOnlySnapshots() {
        let store = SelectionStore()
        store.publish(snapshot(text: "   \n\t "))
        #expect(store.read().isEmpty)
    }

    @Test func publishingASecondSelectionInTheSameDocumentSupersedesTheFirst() {
        let store = SelectionStore()
        let documentID = DocumentID()
        store.publish(snapshot(documentID: documentID, text: "first", version: 1))
        let second = snapshot(documentID: documentID, text: "second", version: 2)
        store.publish(second)
        let armed = store.read()
        #expect(armed.count == 1)
        #expect(armed.first?.id == second.id)
    }

    @Test func armingSurvivesBeingReadWithoutAck() {
        // Selecting is sharing, with no separate share gesture, and Arming
        // outlives the visible Selection — reading must not itself consume.
        let store = SelectionStore()
        let snap = snapshot()
        store.publish(snap)
        _ = store.read()
        #expect(store.read().map(\.id) == [snap.id])
    }

    @Test func ackRemovesTheAcknowledgedSnapshot() {
        let store = SelectionStore()
        let snap = snapshot()
        store.publish(snap)
        store.ack(snapshotIDs: [snap.id])
        #expect(store.read().isEmpty)
    }

    @Test func ackDoesNotRemoveASnapshotThatAlreadySupersededTheAckedOne() {
        // A newer Selection made between read and ack must survive —
        // acking a stale snapshot id must not clear the new one.
        let store = SelectionStore()
        let documentID = DocumentID()
        let first = snapshot(documentID: documentID, text: "first", version: 1)
        store.publish(first)
        let second = snapshot(documentID: documentID, text: "second", version: 2)
        store.publish(second)
        store.ack(snapshotIDs: [first.id])
        #expect(store.read().map(\.id) == [second.id])
    }

    @Test func explicitClearRemovesTheArmedSnapshot() {
        let store = SelectionStore()
        let documentID = DocumentID()
        let snap = snapshot(documentID: documentID)
        store.publish(snap)
        store.clear(documentID: documentID)
        #expect(store.read().isEmpty)
    }

    @Test func versionedClearIsANoOpAgainstANewerSnapshot() {
        let store = SelectionStore()
        let documentID = DocumentID()
        store.publish(snapshot(documentID: documentID, version: 1))
        let second = snapshot(documentID: documentID, version: 2)
        store.publish(second)
        store.clear(documentID: documentID, version: 1)
        #expect(store.read().map(\.id) == [second.id])
    }

    @Test func readOrdersMostRecentlySelectedFirst() {
        let store = SelectionStore()
        let older = snapshot(text: "older", createdAt: Date(timeIntervalSince1970: 0))
        let newer = snapshot(text: "newer", createdAt: Date(timeIntervalSince1970: 100))
        store.publish(older)
        store.publish(newer)
        #expect(store.read().map(\.id) == [newer.id, older.id])
    }
}

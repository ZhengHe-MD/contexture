import Foundation
import Testing
@testable import ContextureKit

@Suite struct SelectionSnapshotTests {
    private func makeSnapshot(sourceBytes: String, version: Int = 1) -> SelectionSnapshot {
        let data = Data(sourceBytes.utf8)
        return SelectionSnapshot(
            documentID: DocumentID(),
            sourceBytes: data,
            format: .markdown,
            relativePath: "notes.md",
            revision: RevisionHash(contentBytes: data),
            byteRange: SourceByteRange(lowerBound: 0, upperBound: data.count),
            sharingMode: .nextPrompt,
            createdAt: Date(timeIntervalSince1970: 0),
            sourceWindow: SourceWindowID(),
            version: version
        )
    }

    @Test func emptySourceIsEffectivelyEmpty() {
        #expect(makeSnapshot(sourceBytes: "").isEffectivelyEmpty)
    }

    @Test func whitespaceOnlySourceIsEffectivelyEmpty() {
        #expect(makeSnapshot(sourceBytes: "   \n\t  ").isEffectivelyEmpty)
    }

    @Test func nonEmptySourceIsNotEffectivelyEmpty() {
        #expect(!makeSnapshot(sourceBytes: "hello world").isEffectivelyEmpty)
    }

    @Test func revisionHashIsDeterministicForIdenticalBytes() {
        let a = RevisionHash(contentBytes: Data("same content".utf8))
        let b = RevisionHash(contentBytes: Data("same content".utf8))
        #expect(a == b)
    }

    @Test func revisionHashDiffersForDifferentBytes() {
        let a = RevisionHash(contentBytes: Data("content a".utf8))
        let b = RevisionHash(contentBytes: Data("content b".utf8))
        #expect(a != b)
    }

    @Test func byteRangeReportsEmptyWhenBoundsAreEqual() {
        #expect(SourceByteRange(lowerBound: 5, upperBound: 5).isEmpty)
    }

    @Test func byteRangeCountsBytesBetweenBounds() {
        #expect(SourceByteRange(lowerBound: 2, upperBound: 9).count == 7)
    }
}

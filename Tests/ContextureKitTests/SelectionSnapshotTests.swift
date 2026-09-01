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
            absolutePath: "/tmp/notes.md",
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

    // MARK: absolutePath never leaves the Bridge (ADR-0004, issue #8)

    @Test func encodingNeverIncludesTheAbsolutePath() throws {
        let sentinel = "/Users/writer/super-secret-project-name/notes.md"
        let snap = SelectionSnapshot(
            documentID: DocumentID(),
            sourceBytes: Data("hello".utf8),
            format: .markdown,
            relativePath: "notes.md",
            absolutePath: sentinel,
            revision: RevisionHash(contentBytes: Data("hello".utf8)),
            byteRange: SourceByteRange(lowerBound: 0, upperBound: 5),
            sharingMode: .nextPrompt,
            createdAt: Date(),
            sourceWindow: SourceWindowID(),
            version: 1
        )
        let json = try JSONEncoder().encode(snap)
        let jsonText = String(decoding: json, as: UTF8.self)
        #expect(!jsonText.contains(sentinel))
        #expect(!jsonText.contains("super-secret-project-name"))
        #expect(!jsonText.contains("absolutePath"))
    }

    @Test func decodingProducesAnEmptyAbsolutePath() throws {
        // The one place a snapshot is ever decoded (the /publish HTTP
        // route) is not exercised by the app itself today — publishing
        // happens in-process — but a decoded snapshot must still be a safe,
        // well-defined value rather than a crash or a stale/garbage path.
        let snap = makeSnapshot(sourceBytes: "hello")
        let json = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(SelectionSnapshot.self, from: json)
        #expect(decoded.absolutePath.isEmpty)
        #expect(decoded.relativePath == snap.relativePath)
        #expect(decoded.id == snap.id)
    }
}

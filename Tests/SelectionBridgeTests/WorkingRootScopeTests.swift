import ContextureKit
import Foundation
import Testing
@testable import SelectionBridge

@Suite struct WorkingRootScopeTests {
    private func snapshot(
        text: String = "selected",
        absolutePath: String,
        createdAt: Date = Date()
    ) -> SelectionSnapshot {
        let data = Data(text.utf8)
        return SelectionSnapshot(
            documentID: DocumentID(),
            sourceBytes: data,
            format: .markdown,
            relativePath: "placeholder.md",
            absolutePath: absolutePath,
            revision: RevisionHash(contentBytes: data),
            byteRange: SourceByteRange(lowerBound: 0, upperBound: data.count),
            sharingMode: .nextPrompt,
            createdAt: createdAt,
            sourceWindow: SourceWindowID(),
            version: 1
        )
    }

    @Test func includesADocumentUnderTheWorkingRoot() {
        let snap = snapshot(absolutePath: "/Users/writer/project/notes.md")
        let result = WorkingRootScope.apply(to: [snap], workingRoot: "/Users/writer/project")
        #expect(result.map(\.id) == [snap.id])
    }

    @Test func includesADocumentInASubdirectoryOfTheWorkingRoot() {
        let snap = snapshot(absolutePath: "/Users/writer/project/docs/notes.md")
        let result = WorkingRootScope.apply(to: [snap], workingRoot: "/Users/writer/project")
        #expect(result.map(\.id) == [snap.id])
    }

    @Test func excludesADocumentOutsideTheWorkingRoot() {
        let snap = snapshot(absolutePath: "/Users/writer/other/notes.md")
        let result = WorkingRootScope.apply(to: [snap], workingRoot: "/Users/writer/project")
        #expect(result.isEmpty)
    }

    @Test func excludesASiblingDirectoryThatMerelySharesAPrefix() {
        // The classic naive-string-prefix bug: "/Users/writer/project-other"
        // starts with "/Users/writer/project" as a raw string, but is not
        // *under* it as a directory.
        let snap = snapshot(absolutePath: "/Users/writer/project-other/notes.md")
        let result = WorkingRootScope.apply(to: [snap], workingRoot: "/Users/writer/project")
        #expect(result.isEmpty)
    }

    @Test func excludesTheWorkingRootPathItself() {
        // A Document must be strictly *under* the root (a file inside a
        // directory), not the root path verbatim.
        let snap = snapshot(absolutePath: "/Users/writer/project")
        let result = WorkingRootScope.apply(to: [snap], workingRoot: "/Users/writer/project")
        #expect(result.isEmpty)
    }

    @Test func computesTheRelativePathAgainstTheWorkingRoot() {
        let snap = snapshot(absolutePath: "/Users/writer/project/docs/notes.md")
        let result = WorkingRootScope.apply(to: [snap], workingRoot: "/Users/writer/project")
        #expect(result.first?.relativePath == "docs/notes.md")
    }

    @Test func neverDisclosesTheAbsolutePathAsTheRelativePath() {
        let snap = snapshot(absolutePath: "/Users/writer/project/notes.md")
        let result = WorkingRootScope.apply(to: [snap], workingRoot: "/Users/writer/project")
        #expect(result.first?.relativePath == "notes.md")
        #expect(result.first?.relativePath.contains("/Users") != true)
    }

    @Test func normalizesDotSegmentsBeforeMatching() {
        let snap = snapshot(absolutePath: "/Users/writer/project/notes.md")
        let result = WorkingRootScope.apply(to: [snap], workingRoot: "/Users/writer/other/../project")
        #expect(result.map(\.id) == [snap.id])
    }

    @Test func aMissingWorkingRootReturnsNothing() {
        let snap = snapshot(absolutePath: "/Users/writer/project/notes.md")
        #expect(WorkingRootScope.apply(to: [snap], workingRoot: nil).isEmpty)
    }

    @Test func anEmptyWorkingRootReturnsNothing() {
        let snap = snapshot(absolutePath: "/Users/writer/project/notes.md")
        #expect(WorkingRootScope.apply(to: [snap], workingRoot: "").isEmpty)
    }

    @Test func theRootDirectoryItselfAsWorkingRootReturnsNothing() {
        // "/" would match every absolute path there is — an explicit
        // safeguard against that degenerate case.
        let snap = snapshot(absolutePath: "/Users/writer/project/notes.md")
        #expect(WorkingRootScope.apply(to: [snap], workingRoot: "/").isEmpty)
    }

    @Test func preservesMostRecentFirstOrderingAmongMatchingDocuments() {
        let older = snapshot(text: "older", absolutePath: "/root/a.md", createdAt: Date(timeIntervalSince1970: 0))
        let newer = snapshot(text: "newer", absolutePath: "/root/b.md", createdAt: Date(timeIntervalSince1970: 100))
        let result = WorkingRootScope.apply(to: [newer, older], workingRoot: "/root")
        #expect(result.map(\.id) == [newer.id, older.id])
    }

    @Test func aSingleOversizedSnapshotIsTruncatedWithAVisibleMarker() {
        let hugeText = String(repeating: "a", count: WorkingRootScope.maxSnapshotBytes + 5_000)
        let snap = snapshot(text: hugeText, absolutePath: "/root/notes.md")
        let result = WorkingRootScope.apply(to: [snap], workingRoot: "/root")
        let resultText = result.first.map { String(decoding: $0.sourceBytes, as: UTF8.self) }
        #expect(result.first!.sourceBytes.count <= WorkingRootScope.maxSnapshotBytes)
        #expect(resultText?.contains("truncated") == true)
    }

    @Test func perSnapshotTruncationNeverSplitsAMultiByteCharacter() {
        // A snapshot made entirely of a 4-byte-UTF-8 emoji, sized so a naive
        // byte-count truncation would land mid-character.
        let emoji = "😀" // 4 UTF-8 bytes
        let hugeText = String(repeating: emoji, count: (WorkingRootScope.maxSnapshotBytes / 4) + 100)
        let snap = snapshot(text: hugeText, absolutePath: "/root/notes.md")
        let result = WorkingRootScope.apply(to: [snap], workingRoot: "/root")
        #expect(String(data: result.first!.sourceBytes, encoding: .utf8) != nil)
    }

    @Test func exceedingTheTotalCapDropsTheLeastRecentSnapshotsFirst() {
        // Each chunk is larger than maxSnapshotBytes, so per-snapshot
        // capping runs first and caps every one of these down to exactly
        // maxSnapshotBytes — maxTotalBytes is an exact multiple of that
        // (128_000 / 32_000 == 4), so 4 fully-capped snapshots exactly fill
        // the total cap and a 5th must be dropped entirely.
        let chunk = String(repeating: "x", count: WorkingRootScope.maxSnapshotBytes + 5_000)
        let snapshots = (0..<5).map { index in
            snapshot(
                text: chunk,
                absolutePath: "/root/doc\(index).md",
                createdAt: Date(timeIntervalSince1970: TimeInterval(500 - index * 100))
            )
        }
        // Store ordering is already most-recent-first; snapshots[0] is newest.
        let result = WorkingRootScope.apply(to: snapshots, workingRoot: "/root")
        #expect(result.map(\.id) == snapshots.prefix(4).map(\.id))
        #expect(!result.map(\.id).contains(snapshots[4].id))
    }

    @Test func totalCapIsNeverExceededAcrossMultipleSnapshots() {
        let chunk = String(repeating: "x", count: WorkingRootScope.maxSnapshotBytes + 5_000)
        let snapshots = (0..<5).map { index in
            snapshot(
                text: chunk,
                absolutePath: "/root/doc\(index).md",
                createdAt: Date(timeIntervalSince1970: TimeInterval(500 - index * 100))
            )
        }
        let result = WorkingRootScope.apply(to: snapshots, workingRoot: "/root")
        let total = result.reduce(0) { $0 + $1.sourceBytes.count }
        #expect(total <= WorkingRootScope.maxTotalBytes)
    }
}

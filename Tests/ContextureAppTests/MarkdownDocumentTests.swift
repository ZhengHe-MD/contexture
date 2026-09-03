import Foundation
import Testing
@testable import ContextureApp

@Suite struct MarkdownDocumentTests {
    @Test func readDecodesUTF8Bytes() throws {
        let doc = MarkdownDocument()
        try doc.read(from: Data("# Hello".utf8), ofType: "md")
        #expect(doc.text == "# Hello")
    }

    @Test func dataRoundTripsExactBytes() throws {
        let doc = MarkdownDocument()
        try doc.read(from: Data("hello\nworld".utf8), ofType: "md")
        let data = try doc.data(ofType: "md")
        #expect(String(decoding: data, as: UTF8.self) == "hello\nworld")
    }

    @Test func readRejectsInvalidUTF8() {
        let doc = MarkdownDocument()
        let invalidUTF8 = Data([0xFF, 0xFE, 0xFD])
        #expect(throws: (any Error).self) {
            try doc.read(from: invalidUTF8, ofType: "md")
        }
    }

    @Test func updateTextUpdatesTextAndMarksEdited() {
        let doc = MarkdownDocument()
        #expect(doc.text == "")
        doc.updateText("new content")
        #expect(doc.text == "new content")
        #expect(doc.isDocumentEdited)
    }

    @Test func updateTextIsNoOpWhenTextIsUnchanged() {
        let doc = MarkdownDocument()
        doc.updateText("content")
        doc.updateChangeCount(.changeCleared)
        doc.updateText("content")
        #expect(!doc.isDocumentEdited)
    }

    @Test @MainActor func repeatedSaveActionsDoNotBlockTheMainThread() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("contexture-repeated-save-\(UUID().uuidString).md")
        try Data("before".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let doc = MarkdownDocument()
        let controller = EditorWindowController(frameAutosaveName: nil)
        doc.addWindowController(controller)
        controller.windowDidLoad()
        doc.fileURL = url
        doc.fileType = "md"
        doc.updateText("after")
        defer {
            doc.removeWindowController(controller)
            controller.close()
        }

        // A second Command-S can arrive before WebKit answers the first
        // save's asynchronous content query. It must not synchronously wait
        // for a completion that itself needs the blocked main thread.
        let started = Date()
        doc.save(nil)
        doc.save(nil)
        let elapsed = Date().timeIntervalSince(started)

        #expect(elapsed < 1)
    }

    private func selectionChange(text: String = "hello") -> EditorSelectionChange {
        EditorSelectionChange(text: text, byteStart: 0, byteEnd: text.utf8.count, line: 1, column: 1)
    }

    /// A Document with a `fileURL` already set — and, critically, a real
    /// (if empty) file actually present at that path — for tests that call
    /// `publishSelection`.
    ///
    /// Two independent reasons this needs a real `fileURL` rather than
    /// none: `publishSelection` reads `relativePathForSharing`, which falls
    /// back to `NSDocument.displayName` when `fileURL` is nil — and
    /// `displayName`'s AppKit implementation is not safe to call off the
    /// main thread. In the real app that's a non-issue (`publishSelection`
    /// only ever runs on the main thread, driven by a WKScriptMessageHandler
    /// callback), but Swift Testing runs `@Test` functions on a background
    /// cooperative thread pool by default, and calling `displayName` from
    /// there crashed intermittently (confirmed via the crash reporter's
    /// `.ips` log, which showed the fault inside `-[NSDocument
    /// displayName]` on `com.apple.root.default-qos.cooperative`).
    ///
    /// Separately (issue #7): `publishSelection` now flushes to disk before
    /// Arming, and Arms from whatever it can actually read back off disk —
    /// a `fileURL` pointing at nothing (no file created) makes that read
    /// fail and the whole publish silently becomes a no-op, which is
    /// correct production behavior but means these tests need a real file
    /// on disk, not just a path, to exercise the Arming behavior they're
    /// actually testing.
    private func documentForSelection() -> MarkdownDocument {
        let doc = MarkdownDocument()
        let url = URL(fileURLWithPath: "/tmp/contexture-test-\(UUID().uuidString).md")
        try! Data().write(to: url)
        doc.fileURL = url
        doc.fileType = "md"
        return doc
    }

    // MARK: Arming lifecycle (issue #6)

    @Test func publishSelectionArmsASnapshotForThisDocument() {
        let doc = documentForSelection()
        #expect(!AppServices.bridgeServer.isArmed(documentID: doc.documentID))
        doc.publishSelection(selectionChange())
        #expect(AppServices.bridgeServer.isArmed(documentID: doc.documentID))
    }

    @Test func editingClearsAPreviouslyArmedSnapshot() {
        // Arming survives the visible Selection collapsing, but an edit is
        // different: it invalidates the Snapshot by revision mismatch
        // (docs/architecture/selection-bridge.md "Lifecycle and
        // deduplication").
        let doc = documentForSelection()
        doc.publishSelection(selectionChange())
        #expect(AppServices.bridgeServer.isArmed(documentID: doc.documentID))
        doc.updateText("something the writer typed")
        #expect(!AppServices.bridgeServer.isArmed(documentID: doc.documentID))
    }

    @Test func updateTextWithNoActualChangeDoesNotClearArming() {
        // updateText is a no-op when the text is unchanged; it must not
        // clear an Armed Snapshot in that case either.
        //
        // Publishes on a clean (not-yet-edited) Document deliberately: a
        // dirty Document's publishSelection flushes to disk first (issue
        // #7), which is asynchronous, and this test needs Arming to have
        // already happened by the time it asserts. A clean Document takes
        // publishSelection's synchronous read-current-disk-content path
        // instead (see armFromCurrentDisk() in MarkdownDocument.swift).
        let doc = documentForSelection()
        doc.publishSelection(selectionChange())
        #expect(AppServices.bridgeServer.isArmed(documentID: doc.documentID))
        doc.updateText("")
        #expect(AppServices.bridgeServer.isArmed(documentID: doc.documentID))
    }

    @Test func closingADocumentClearsItsArmedSnapshot() {
        // Exercises the close() override's clearing logic directly rather
        // than calling the real NSDocument.close() — see
        // clearArmedSnapshotForClose()'s doc comment for why that's unsafe
        // in a headless unit test.
        let doc = documentForSelection()
        doc.publishSelection(selectionChange())
        #expect(AppServices.bridgeServer.isArmed(documentID: doc.documentID))
        doc.clearArmedSnapshotForClose()
        #expect(!AppServices.bridgeServer.isArmed(documentID: doc.documentID))
    }

    @Test func clearArmedSnapshotActionClearsTheArmedSnapshot() {
        let doc = documentForSelection()
        doc.publishSelection(selectionChange())
        #expect(AppServices.bridgeServer.isArmed(documentID: doc.documentID))
        doc.clearArmedSnapshot(nil)
        #expect(!AppServices.bridgeServer.isArmed(documentID: doc.documentID))
    }

    // MARK: Sharing Mode (issue #6)

    @Test func sharingModeDefaultsToNextPrompt() {
        #expect(MarkdownDocument().sharingMode == .nextPrompt)
    }

    @Test func offSharingModeNeverArmsASnapshot() {
        let doc = documentForSelection()
        doc.setSharingMode(.off)
        doc.publishSelection(selectionChange())
        #expect(!AppServices.bridgeServer.isArmed(documentID: doc.documentID))
    }

    @Test func switchingToOffClearsAnAlreadyArmedSnapshot() {
        // Off means no Selection Context is made available at all
        // (docs/product.md "Sharing modes") — that must hold immediately
        // for whatever is already Armed, not just for the next Selection.
        let doc = documentForSelection()
        doc.publishSelection(selectionChange())
        #expect(AppServices.bridgeServer.isArmed(documentID: doc.documentID))
        doc.setSharingMode(.off)
        #expect(!AppServices.bridgeServer.isArmed(documentID: doc.documentID))
    }

    @Test func switchingBackToNextPromptDoesNotRetroactivelyArmAnything() {
        // Selecting is sharing — turning Sharing back on must not, by
        // itself, Arm whatever was selected while Off was active.
        let doc = documentForSelection()
        doc.setSharingMode(.off)
        doc.publishSelection(selectionChange())
        doc.setSharingMode(.nextPrompt)
        #expect(!AppServices.bridgeServer.isArmed(documentID: doc.documentID))
    }

    @Test func sharingModePersistsAcrossSelections() {
        let doc = documentForSelection()
        doc.setSharingMode(.off)
        doc.publishSelection(selectionChange(text: "first"))
        doc.publishSelection(selectionChange(text: "second"))
        #expect(doc.sharingMode == .off)
        #expect(!AppServices.bridgeServer.isArmed(documentID: doc.documentID))
    }

    @Test func settingSharingModeToItsCurrentValueIsANoOp() {
        // Switching to Off clears any already-Armed Snapshot as a side
        // effect; re-affirming the mode that's already active must not.
        let doc = documentForSelection()
        doc.publishSelection(selectionChange())
        doc.setSharingMode(.nextPrompt)
        #expect(AppServices.bridgeServer.isArmed(documentID: doc.documentID))
    }
}

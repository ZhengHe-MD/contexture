import Foundation
import Testing
import ContextureKit
@testable import ContextureApp

@Suite struct HTMLDocumentTests {
    @Test func formatIsHTML() {
        let doc = HTMLDocument()
        #expect(doc.format == .html)
    }

    @Test func readDecodesUTF8Bytes() throws {
        let doc = HTMLDocument()
        try doc.read(from: Data("<h1>Hello</h1>".utf8), ofType: "html")
        #expect(doc.text == "<h1>Hello</h1>")
    }

    @Test func dataRoundTripsExactBytes() throws {
        let doc = HTMLDocument()
        try doc.read(from: Data("<p>hello</p>\n<div>world</div>".utf8), ofType: "html")
        let data = try doc.data(ofType: "html")
        #expect(String(decoding: data, as: UTF8.self) == "<p>hello</p>\n<div>world</div>")
    }

    @Test func readRejectsInvalidUTF8() {
        let doc = HTMLDocument()
        let invalidUTF8 = Data([0xFF, 0xFE, 0xFD])
        #expect(throws: (any Error).self) {
            try doc.read(from: invalidUTF8, ofType: "html")
        }
    }

    @Test func updateTextUpdatesTextAndMarksEdited() {
        let doc = HTMLDocument()
        #expect(doc.text == "")
        doc.updateText("<p>new content</p>")
        #expect(doc.text == "<p>new content</p>")
        #expect(doc.isDocumentEdited)
    }

    @Test func updateTextIsNoOpWhenTextIsUnchanged() {
        let doc = HTMLDocument()
        doc.updateText("<p>content</p>")
        doc.updateChangeCount(.changeCleared)
        doc.updateText("<p>content</p>")
        #expect(!doc.isDocumentEdited)
    }

    private func selectionChange(text: String = "<p>hello</p>") -> EditorSelectionChange {
        EditorSelectionChange(text: text, byteStart: 0, byteEnd: text.utf8.count, line: 1, column: 1)
    }

    private func documentForSelection() -> HTMLDocument {
        let doc = HTMLDocument()
        let url = URL(fileURLWithPath: "/tmp/contexture-test-\(UUID().uuidString).html")
        try! Data().write(to: url)
        doc.fileURL = url
        doc.fileType = "html"
        return doc
    }

    // MARK: Arming and HTML format tag

    @Test func publishSelectionArmsASnapshotWithHTMLFormatTag() {
        let doc = documentForSelection()
        #expect(!AppServices.bridgeServer.isArmed(documentID: doc.documentID))
        doc.publishSelection(selectionChange())
        #expect(AppServices.bridgeServer.isArmed(documentID: doc.documentID))

        let snapshots = AppServices.bridgeServer.read(workingRoot: "/tmp")
        let snapshot = snapshots.first { $0.documentID == doc.documentID }
        #expect(snapshot != nil)
        #expect(snapshot?.format == .html)
    }

    @Test func editingClearsAPreviouslyArmedSnapshot() {
        let doc = documentForSelection()
        doc.publishSelection(selectionChange())
        #expect(AppServices.bridgeServer.isArmed(documentID: doc.documentID))
        doc.updateText("<p>something typed</p>")
        #expect(!AppServices.bridgeServer.isArmed(documentID: doc.documentID))
    }

    @Test func updateTextWithNoActualChangeDoesNotClearArming() {
        let doc = documentForSelection()
        doc.publishSelection(selectionChange())
        #expect(AppServices.bridgeServer.isArmed(documentID: doc.documentID))
        doc.updateText("")
        #expect(AppServices.bridgeServer.isArmed(documentID: doc.documentID))
    }

    @Test func closingADocumentClearsItsArmedSnapshot() {
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

    // MARK: Sharing Mode

    @Test func sharingModeDefaultsToNextPrompt() {
        #expect(HTMLDocument().sharingMode == .nextPrompt)
    }

    @Test func offSharingModeNeverArmsASnapshot() {
        let doc = documentForSelection()
        doc.setSharingMode(.off)
        doc.publishSelection(selectionChange())
        #expect(!AppServices.bridgeServer.isArmed(documentID: doc.documentID))
    }

    @Test func switchingToOffClearsAnAlreadyArmedSnapshot() {
        let doc = documentForSelection()
        doc.publishSelection(selectionChange())
        #expect(AppServices.bridgeServer.isArmed(documentID: doc.documentID))
        doc.setSharingMode(.off)
        #expect(!AppServices.bridgeServer.isArmed(documentID: doc.documentID))
    }

    @Test func switchingBackToNextPromptDoesNotRetroactivelyArmAnything() {
        let doc = documentForSelection()
        doc.setSharingMode(.off)
        doc.publishSelection(selectionChange())
        doc.setSharingMode(.nextPrompt)
        #expect(!AppServices.bridgeServer.isArmed(documentID: doc.documentID))
    }

    @Test func sharingModePersistsAcrossSelections() {
        let doc = documentForSelection()
        doc.setSharingMode(.off)
        doc.publishSelection(selectionChange(text: "<p>first</p>"))
        doc.publishSelection(selectionChange(text: "<p>second</p>"))
        #expect(doc.sharingMode == .off)
        #expect(!AppServices.bridgeServer.isArmed(documentID: doc.documentID))
    }
}

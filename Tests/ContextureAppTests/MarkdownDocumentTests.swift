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
}

import Foundation
import Testing
@testable import ContextureApp

@Suite struct EditorBridgeTests {
    private final class DelegateSpy: EditorBridgeDelegate {
        var titleChangeCount = 0
        var lastTitle: String?

        func editorBridgeDidBecomeReady() {}
        func editorBridgeContentDidChange(_ text: String) {}
        func editorBridgeSelectionDidChange(_ change: EditorSelectionChange) {}
        func editorBridgePreviewHTMLDidChange(_ html: String) {}

        func editorBridgeDocumentTitleDidChange(_ title: String?) {
            titleChangeCount += 1
            lastTitle = title
        }
    }

    @Test func documentMetadataMessagePublishesTheFrontMatterTitle() {
        let delegate = DelegateSpy()
        let handler = EditorBridgeMessageHandler()
        handler.delegate = delegate

        handler.handleMessageBody([
            "type": "documentMetadataChanged",
            "title": "A Writer's Page",
        ])

        #expect(delegate.titleChangeCount == 1)
        #expect(delegate.lastTitle == "A Writer's Page")
    }

    @Test func nullDocumentTitlePublishesTheFilenameFallbackSignal() {
        let delegate = DelegateSpy()
        let handler = EditorBridgeMessageHandler()
        handler.delegate = delegate

        handler.handleMessageBody([
            "type": "documentMetadataChanged",
            "title": NSNull(),
        ])

        #expect(delegate.titleChangeCount == 1)
        #expect(delegate.lastTitle == nil)
    }
}

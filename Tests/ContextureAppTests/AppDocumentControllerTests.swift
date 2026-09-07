import Foundation
import Testing
@testable import ContextureApp

// DocumentTypeRegistry only — AppDocumentController itself is an
// NSDocumentController subclass, and AppKit crashes if more than one shared
// instance is ever created, which a per-test instantiation would trigger.
@Suite struct DocumentTypeRegistryTests {
    @Test func mapsMarkdownExtensionsToMarkdownDocument() {
        let registry = DocumentTypeRegistry()
        #expect(registry.documentClass(forExtension: "md") == MarkdownDocument.self)
        #expect(registry.documentClass(forExtension: "markdown") == MarkdownDocument.self)
    }

    @Test func mapsHTMLExtensionsToHTMLDocumentCaseInsensitively() {
        let registry = DocumentTypeRegistry()
        #expect(registry.documentClass(forExtension: "html") == HTMLDocument.self)
        #expect(registry.documentClass(forExtension: "htm") == HTMLDocument.self)
        #expect(registry.documentClass(forExtension: "HTML") == HTMLDocument.self)
        #expect(registry.documentClass(forExtension: "HTM") == HTMLDocument.self)
        #expect(registry.documentClass(forExtension: "Html") == HTMLDocument.self)
    }

    @Test func fallsBackToMarkdownForAnUnknownExtension() {
        let registry = DocumentTypeRegistry()
        #expect(registry.documentClass(forExtension: "unknown") == MarkdownDocument.self)
    }

    @Test func defaultExtensionIsMarkdown() {
        #expect(DocumentTypeRegistry().defaultExtension == "md")
    }
}

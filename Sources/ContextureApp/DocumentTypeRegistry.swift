/// Maps a Document's file extension to its NSDocument subclass. Kept
/// independent of `NSDocumentController` (which enforces a single shared
/// instance app-wide and cannot safely be instantiated per test) so the
/// mapping itself stays unit-testable.
///
/// Maps Markdown (.md, .markdown) to `MarkdownDocument` and HTML (.html, .htm)
/// to `HTMLDocument` case-insensitively.
struct DocumentTypeRegistry {
    let defaultExtension = "md"

    private let typesByExtension: [String: ContextureDocument.Type] = [
        "md": MarkdownDocument.self,
        "markdown": MarkdownDocument.self,
        "html": HTMLDocument.self,
        "htm": HTMLDocument.self,
    ]

    func documentClass(forExtension extensionName: String) -> ContextureDocument.Type {
        typesByExtension[extensionName.lowercased()] ?? MarkdownDocument.self
    }
}

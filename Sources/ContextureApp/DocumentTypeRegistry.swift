/// Maps a Document's file extension to its NSDocument subclass. Kept
/// independent of `NSDocumentController` (which enforces a single shared
/// instance app-wide and cannot safely be instantiated per test) so the
/// mapping itself stays unit-testable.
///
/// A second Document format (docs/product.md names HTML, SVG, and Mermaid as
/// the natural next ones) is a new entry in `typesByExtension`, not a
/// rewrite of `AppDocumentController`.
struct DocumentTypeRegistry {
    let defaultExtension = "md"

    private let typesByExtension: [String: MarkdownDocument.Type] = [
        "md": MarkdownDocument.self,
        "markdown": MarkdownDocument.self,
    ]

    func documentClass(forExtension extensionName: String) -> MarkdownDocument.Type {
        typesByExtension[extensionName] ?? MarkdownDocument.self
    }
}

import ContextureKit

/// A Document (CONTEXT.md) backed by a local Markdown file.
final class MarkdownDocument: ContextureDocument {
    override var format: FormatTag { .markdown }
}

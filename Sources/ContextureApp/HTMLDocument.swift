import ContextureKit

/// A Document (CONTEXT.md) backed by a local HTML file (`.html` or `.htm`).
final class HTMLDocument: ContextureDocument {
    override var format: FormatTag { .html }
}

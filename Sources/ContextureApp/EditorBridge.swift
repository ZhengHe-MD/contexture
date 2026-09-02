import WebKit

/// A non-empty Selection reported by the editor bundle's JS. Byte offsets
/// are canonical UTF-8 offsets into the Document's Source, already
/// converted from CodeMirror's UTF-16 positions in JS (see
/// editor-web/src/main.js) — this is the write authority the architecture
/// doc calls for, not a UI-native range.
struct EditorSelectionChange {
    let text: String
    let byteStart: Int
    let byteEnd: Int
    let line: Int?
    let column: Int?
}

/// Receives messages posted from the editor bundle's JS (see
/// editor-web/src/main.js) via `window.webkit.messageHandlers.contexture`.
protocol EditorBridgeDelegate: AnyObject {
    func editorBridgeDidBecomeReady()
    func editorBridgeContentDidChange(_ text: String)
    func editorBridgeSelectionDidChange(_ change: EditorSelectionChange)
    /// `html` is the Source rendered to HTML by `markdown-it` in
    /// editor-web/src/main.js, with Mermaid Blocks already replaced by inert
    /// SVG data images. It remains untrusted (GFM raw HTML passthrough is on)
    /// and is not yet sanitized or CSP-wrapped for the Preview pane. See
    /// `PreviewDocumentBuilder` and ADR-0005.
    func editorBridgePreviewHTMLDidChange(_ html: String)
}

/// `WKScriptMessageHandler` is a strong-retaining relationship from the
/// `WKUserContentController`, so this stays a small, standalone object
/// (rather than the view controller itself) to keep the WKWebView from
/// indirectly retaining its owner past teardown.
final class EditorBridgeMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: EditorBridgeDelegate?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            delegate?.editorBridgeDidBecomeReady()
        case "contentChanged":
            if let text = body["text"] as? String {
                delegate?.editorBridgeContentDidChange(text)
            }
        case "selectionChanged":
            if let text = body["text"] as? String,
               let byteStart = body["byteStart"] as? Int,
               let byteEnd = body["byteEnd"] as? Int {
                let change = EditorSelectionChange(
                    text: text,
                    byteStart: byteStart,
                    byteEnd: byteEnd,
                    line: body["line"] as? Int,
                    column: body["column"] as? Int
                )
                delegate?.editorBridgeSelectionDidChange(change)
            }
        case "previewHTML":
            if let html = body["html"] as? String {
                delegate?.editorBridgePreviewHTMLDidChange(html)
            }
        default:
            break
        }
    }
}

import WebKit

/// Receives messages posted from the editor bundle's JS (see
/// editor-web/src/main.js) via `window.webkit.messageHandlers.contexture`.
protocol EditorBridgeDelegate: AnyObject {
    func editorBridgeDidBecomeReady()
    func editorBridgeContentDidChange(_ text: String)
    /// `html` is the Source rendered to HTML by `markdown-it` in
    /// editor-web/src/main.js — untrusted (GFM raw HTML passthrough is on),
    /// and not yet sanitized or CSP-wrapped for the Preview pane. See
    /// `PreviewDocumentBuilder`.
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
        case "previewHTML":
            if let html = body["html"] as? String {
                delegate?.editorBridgePreviewHTMLDidChange(html)
            }
        default:
            break
        }
    }
}

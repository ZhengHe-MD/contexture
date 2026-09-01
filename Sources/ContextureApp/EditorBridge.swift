import WebKit

/// Receives messages posted from the editor bundle's JS (see
/// editor-web/src/main.js) via `window.webkit.messageHandlers.contexture`.
protocol EditorBridgeDelegate: AnyObject {
    func editorBridgeDidBecomeReady()
    func editorBridgeContentDidChange(_ text: String)
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
        default:
            break
        }
    }
}

import AppKit
import WebKit

/// Hosts the Source and Preview panes side by side in one `WKWebView`, per
/// ADR-0002 ("the split divider is CSS inside the web view rather than an
/// NSSplitView"). Owns nothing about NSDocument; it only reports raw text
/// changes and answers for the editor's current content on demand.
///
/// The Source pane (CodeMirror) and the outer page's own JS (which turns
/// Source into Preview HTML via markdown-it — editor-web/src/main.js) are
/// trusted first-party content and need JavaScript, so this WKWebView keeps
/// JS enabled overall. The Preview pane is instead isolated at the DOM
/// level: its content lives in a sandboxed `<iframe>` (no `allow-scripts`)
/// whose `srcdoc` is a document `PreviewDocumentBuilder` sanitizes and
/// wraps in a strict CSP before this controller ever hands it to the web
/// view. See `editorBridgePreviewHTMLDidChange(_:)` below.
final class EditorViewController: NSViewController, EditorBridgeDelegate {
    private let webView: WKWebView
    private let messageHandler = EditorBridgeMessageHandler()
    private var pendingInitialText: String?
    private var isReady = false

    var onContentChanged: ((String) -> Void)?
    var onSelectionChanged: ((EditorSelectionChange) -> Void)?

    init() {
        let configuration = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        configuration.userContentController = contentController
        // This WKWebView runs JavaScript: CodeMirror (Source) needs it, and
        // so does the outer page's own script that renders Source to
        // Preview HTML. Both are trusted first-party content (the bundled
        // editor script). The untrusted part — the Document's own Markdown
        // rendered to HTML, which may contain raw <script>/<img
        // src=remote>/etc. per GFM — never runs as script in this webview
        // at all; it only ever becomes the `srcdoc` of a sandboxed iframe
        // with no `allow-scripts` (see EditorViewController's class doc
        // comment and PreviewDocumentBuilder).
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nil, bundle: nil)
        contentController.add(messageHandler, name: "contexture")
        messageHandler.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let container = NSView()
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let installedResourceBundle = Bundle.main.resourceURL
            .map { $0.appendingPathComponent("Contexture_ContextureApp.bundle", isDirectory: true) }
            .flatMap(Bundle.init(url:))
        guard let indexURL = installedResourceBundle?.url(
            forResource: "index",
            withExtension: "html",
            subdirectory: "editor"
        ) ?? Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "editor") else {
            fatalError("Contexture was built without its bundled editor resources")
        }
        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
    }

    /// Sets the Source shown in the editor. Safe to call before the webview
    /// has finished loading; the text is applied once JS reports readiness.
    func load(initialText: String) {
        if isReady {
            setContent(initialText)
        } else {
            pendingInitialText = initialText
        }
    }

    /// Asks the live editor for its authoritative current text rather than
    /// relying on the last `contentChanged` message, so save is never
    /// racing an in-flight keystroke.
    func fetchCurrentContent(_ completion: @escaping (String?) -> Void) {
        webView.evaluateJavaScript("window.__contexture_getContent()") { result, _ in
            completion(result as? String)
        }
    }

    private func setContent(_ text: String) {
        guard let payload = try? JSONEncoder().encode(text),
              let json = String(data: payload, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.__contexture_setContent(\(json))")
    }

    // MARK: EditorBridgeDelegate

    func editorBridgeDidBecomeReady() {
        isReady = true
        if let text = pendingInitialText {
            setContent(text)
            pendingInitialText = nil
        }
    }

    func editorBridgeContentDidChange(_ text: String) {
        onContentChanged?(text)
    }

    func editorBridgeSelectionDidChange(_ change: EditorSelectionChange) {
        onSelectionChanged?(change)
    }

    /// `html` is untrusted (see the protocol doc comment). It is sanitized
    /// and wrapped in a CSP-bearing document by `PreviewDocumentBuilder`
    /// here in native Swift — not in the web view's own JS — specifically
    /// so this security-relevant transform has ordinary headless Swift unit
    /// test coverage (see PreviewSanitizerTests/PreviewDocumentBuilderTests)
    /// rather than living only in editor-web where this project has no
    /// equivalent headless test setup.
    func editorBridgePreviewHTMLDidChange(_ html: String) {
        let document = PreviewDocumentBuilder.buildDocument(bodyHTML: html)
        guard let payload = try? JSONEncoder().encode(document),
              let json = String(data: payload, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.__contexture_setPreviewHTML(\(json))")
    }
}

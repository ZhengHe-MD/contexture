import AppKit
import WebKit

/// Hosts the Source pane: CodeMirror 6 running inside a `WKWebView`, per
/// ADR-0002. Owns nothing about NSDocument; it only reports raw text changes
/// and answers for the editor's current content on demand.
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
        // No JavaScript execution beyond the bundled editor script is needed,
        // but CodeMirror itself is JS — this pane is trusted first-party
        // content, unlike the Preview pane (issue #4), which renders
        // untrusted Document HTML and must disable JS entirely.
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
        guard let indexURL = Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "editor") else {
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
}

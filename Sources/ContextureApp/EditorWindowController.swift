import AppKit

/// One window per open Document, standard macOS chrome and traffic-light
/// placement (docs/product.md "Writing experience").
final class EditorWindowController: NSWindowController {
    private let editorViewController = EditorViewController()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.setFrameAutosaveName("ContextureEditorWindow")
        window.contentMinSize = NSSize(width: 480, height: 320)
        window.center()
        self.init(window: window)
        window.contentViewController = editorViewController
    }

    /// `windowDidLoad()` is only invoked automatically for a NIB-loaded
    /// window; this window is built in code, so `MarkdownDocument` calls
    /// this explicitly once the document/window-controller relationship is
    /// established via `addWindowController(_:)`.
    override func windowDidLoad() {
        super.windowDidLoad()
        if let markdownDocument = document as? MarkdownDocument {
            editorViewController.load(initialText: markdownDocument.text)
        }
        editorViewController.onContentChanged = { [weak self] newText in
            (self?.document as? MarkdownDocument)?.updateText(newText)
        }
        editorViewController.onSelectionChanged = { [weak self] change in
            (self?.document as? MarkdownDocument)?.publishSelection(change)
        }
    }

    /// Used ahead of save to read the live editor rather than the last
    /// reported `contentChanged` snapshot.
    func currentEditorContent(_ completion: @escaping (String?) -> Void) {
        editorViewController.fetchCurrentContent(completion)
    }
}

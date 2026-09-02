import AppKit

/// One window per open Document, standard macOS chrome and traffic-light
/// placement (docs/product.md "Writing experience").
final class EditorWindowController: NSWindowController {
    static let minimumContentSize = NSSize(width: 480, height: 320)

    private static let fallbackContentSize = NSSize(width: 1200, height: 800)
    private static let initialScreenFraction: CGFloat = 2.0 / 3.0
    private static let frameAutosaveName = "ContextureEditorWindow.v2"

    private let editorViewController = EditorViewController()

    convenience init() {
        let contentSize = Self.defaultContentSize(
            for: NSScreen.main?.visibleFrame.size
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        // The versioned name gives existing installs the larger default once;
        // after that, AppKit continues to remember the size the writer chose.
        window.setFrameAutosaveName(Self.frameAutosaveName)
        window.contentMinSize = Self.minimumContentSize
        window.center()
        self.init(window: window)
        window.contentViewController = editorViewController
    }

    /// Use the available desktop rather than a fixed pixel size so the first
    /// window feels equally substantial on a laptop and an external display.
    static func defaultContentSize(for visibleScreenSize: NSSize?) -> NSSize {
        guard let visibleScreenSize else {
            return fallbackContentSize
        }

        return NSSize(
            width: max(
                minimumContentSize.width,
                (visibleScreenSize.width * initialScreenFraction).rounded(.up)
            ),
            height: max(
                minimumContentSize.height,
                (visibleScreenSize.height * initialScreenFraction).rounded(.up)
            )
        )
    }

    /// `windowDidLoad()` is only invoked automatically for a NIB-loaded
    /// window; this window is built in code, so `MarkdownDocument` calls
    /// this explicitly once the document/window-controller relationship is
    /// established via `addWindowController(_:)`.
    override func windowDidLoad() {
        super.windowDidLoad()
        if let markdownDocument = document as? MarkdownDocument {
            editorViewController.load(initialText: markdownDocument.text)
            let armedIndicator = ArmedIndicatorViewController(
                documentID: markdownDocument.documentID,
                bridgeServer: AppServices.bridgeServer
            )
            window?.addTitlebarAccessoryViewController(armedIndicator)
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

    /// Pushes text into the editor surface without marking the Document
    /// dirty — used when the file on disk changed underneath a clean
    /// buffer (issue #7).
    func reloadContent(_ text: String) {
        editorViewController.load(initialText: text)
    }

    /// A Document with no path cannot publish a Selection Snapshot at all
    /// (ADR-0003: publishing flushes to disk first). `nil` clears the
    /// reason once the Document has somewhere to flush to. Surfaced as the
    /// window's subtitle — separate from whatever Armed-selection indicator
    /// issue #6 adds, since this reflects "can this Document share at all,"
    /// not "is a Selection Armed right now."
    func setCannotShareReason(_ reason: String?) {
        window?.subtitle = reason ?? ""
    }
}

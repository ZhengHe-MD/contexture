import AppKit

/// One window per open Document, standard macOS chrome and traffic-light
/// placement (docs/product.md "Writing experience").
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    static let minimumContentSize = NSSize(width: 480, height: 320)

    private static let fallbackContentSize = NSSize(width: 1200, height: 800)
    private static let initialScreenAreaFraction: CGFloat = 2.0 / 3.0
    private static let frameAutosaveName = "ContextureEditorWindow.v6"

    private let editorViewController = EditorViewController()
    private var frontMatterTitle: String?
    private var hasCompletedInitialFrameCheck = false
    private var isRepairingLegacyMinimumFrame = false

    convenience init() {
        self.init(frameAutosaveName: Self.frameAutosaveName)
    }

    convenience init(frameAutosaveName: String?) {
        let targetScreen = NSScreen.main
        let contentSize = Self.defaultContentSize(
            for: targetScreen?.visibleFrame.size
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        self.init(window: window)

        // Installing a content view controller replaces the window's content
        // view and adopts that view's zero intrinsic size. Do it before frame
        // restoration and sizing; otherwise AppKit clamps the result to the
        // 480 x 320 minimum after the intended frame has already been set.
        window.contentViewController = editorViewController
        window.contentMinSize = Self.minimumContentSize
        window.setContentSize(contentSize)

        if let visibleFrame = targetScreen?.visibleFrame {
            Self.center(window, in: visibleFrame)
        } else {
            window.center()
        }

        // Observe frame restoration, but only after content installation and
        // the intended default size are complete. setFrameAutosaveName(_:) can
        // synchronously restore a legacy minimum frame, before the window is
        // presented or becomes key.
        window.delegate = self
        if let frameAutosaveName {
            // The versioned name discards frames captured before content-view
            // sizing and same-screen centering were corrected. Later user
            // resizing wins.
            window.setFrameAutosaveName(frameAutosaveName)
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard !hasCompletedInitialFrameCheck else { return }
        // NSDocument state restoration runs outside this controller's
        // initializer and can reapply the 480 x 320 frame produced by older
        // builds. Repair that distinctive broken state once it becomes the
        // key window, regardless of which AppKit path displayed it.
        repairLegacyMinimumFrameIfNeeded()
        hasCompletedInitialFrameCheck = true
    }

    func windowDidResize(_ notification: Notification) {
        guard !hasCompletedInitialFrameCheck,
              !isRepairingLegacyMinimumFrame,
              repairLegacyMinimumFrameIfNeeded() else {
            return
        }
    }

    @discardableResult
    private func repairLegacyMinimumFrameIfNeeded() -> Bool {
        guard let window,
              let currentSize = window.contentView?.frame.size,
              currentSize.width <= Self.minimumContentSize.width,
              currentSize.height <= Self.minimumContentSize.height,
              let targetScreen = window.screen ?? NSScreen.main else {
            return false
        }

        isRepairingLegacyMinimumFrame = true
        defer { isRepairingLegacyMinimumFrame = false }
        window.setContentSize(Self.defaultContentSize(for: targetScreen.visibleFrame.size))
        Self.center(window, in: targetScreen.visibleFrame)
        return true
    }

    private static func center(_ window: NSWindow, in visibleFrame: NSRect) {
        let frame = window.frame
        window.setFrameOrigin(NSPoint(
            x: visibleFrame.midX - frame.width / 2.0,
            y: visibleFrame.midY - frame.height / 2.0
        ))
    }

    /// Use the available desktop rather than a fixed pixel size. Scaling both
    /// dimensions by sqrt(2/3) preserves the display shape while giving the
    /// content at least two-thirds of the visible screen area.
    static func defaultContentSize(for visibleScreenSize: NSSize?) -> NSSize {
        guard let visibleScreenSize else {
            return fallbackContentSize
        }

        let linearScale = initialScreenAreaFraction.squareRoot()
        return NSSize(
            width: max(
                minimumContentSize.width,
                (visibleScreenSize.width * linearScale).rounded(.up)
            ),
            height: max(
                minimumContentSize.height,
                (visibleScreenSize.height * linearScale).rounded(.up)
            )
        )
    }

    static func windowTitle(frontMatterTitle: String?, documentDisplayName: String) -> String {
        guard let title = frontMatterTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return documentDisplayName
        }
        return title
    }

    override func windowTitle(forDocumentDisplayName displayName: String) -> String {
        Self.windowTitle(frontMatterTitle: frontMatterTitle, documentDisplayName: displayName)
    }

    private func setFrontMatterTitle(_ title: String?) {
        frontMatterTitle = title
        synchronizeWindowTitleWithDocumentName()
    }

    /// `windowDidLoad()` is only invoked automatically for a NIB-loaded
    /// window; this window is built in code, so `MarkdownDocument` calls
    /// this explicitly once the document/window-controller relationship is
    /// established via `addWindowController(_:)`.
    override func windowDidLoad() {
        super.windowDidLoad()
        editorViewController.onContentChanged = { [weak self] newText in
            (self?.document as? MarkdownDocument)?.updateText(newText)
        }
        editorViewController.onSelectionChanged = { [weak self] change in
            (self?.document as? MarkdownDocument)?.publishSelection(change)
        }
        editorViewController.onDocumentTitleChanged = { [weak self] title in
            self?.setFrontMatterTitle(title)
        }
        if let markdownDocument = document as? MarkdownDocument {
            editorViewController.documentURLProvider = { [weak markdownDocument] in
                markdownDocument?.fileURL
            }
            editorViewController.load(initialText: markdownDocument.text)
            let armedIndicator = ArmedIndicatorViewController(
                documentID: markdownDocument.documentID,
                bridgeServer: AppServices.bridgeServer
            )
            window?.addTitlebarAccessoryViewController(armedIndicator)
        }
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

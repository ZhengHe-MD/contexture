import AppKit
import ContextureKit

/// One window per open Document, standard macOS chrome and traffic-light
/// placement (docs/product.md "Writing experience").
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    static let minimumContentSize = NSSize(width: 480, height: 320)

    private static let fallbackContentSize = NSSize(width: 1200, height: 800)
    private static let initialScreenAreaFraction: CGFloat = 2.0 / 3.0
    private static let frameAutosaveName = "ContextureEditorWindow.v6"

    private let editorViewController: EditorViewController
    private lazy var viewModeAccessory = ViewModeAccessoryViewController(
        initialMode: editorViewController.currentViewMode
    )
    private var frontMatterTitle: String?
    private var hasCompletedInitialFrameCheck = false
    private var isRepairingLegacyMinimumFrame = false
    private var cannotShareReason: String?
    private var previewUnmappableReason: String?

    convenience init() {
        self.init(frameAutosaveName: Self.frameAutosaveName)
    }

    convenience init(frameAutosaveName: String?) {
        self.init(frameAutosaveName: frameAutosaveName, userDefaults: .standard)
    }

    convenience init(frameAutosaveName: String?, userDefaults: UserDefaults) {
        let editorViewController = EditorViewController(userDefaults: userDefaults)
        self.init(frameAutosaveName: frameAutosaveName, editorViewController: editorViewController)
    }

    init(frameAutosaveName: String?, editorViewController: EditorViewController) {
        self.editorViewController = editorViewController
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
        super.init(window: window)

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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferredZoomDidChange(_:)),
            name: DocumentZoom.didChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func preferredZoomDidChange(_ notification: Notification) {
        guard let newFactor = notification.userInfo?[DocumentZoom.factorUserInfoKey] as? Double else { return }
        if notification.object as? EditorViewController !== editorViewController {
            editorViewController.setZoomFactor(newFactor, showHUD: false, persistAsDefault: false)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
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
    /// window; this window is built in code, so `ContextureDocument` calls
    /// this explicitly once the document/window-controller relationship is
    /// established via `addWindowController(_:)`.
    override func windowDidLoad() {
        super.windowDidLoad()
        editorViewController.onContentChanged = { [weak self] newText in
            (self?.document as? ContextureDocument)?.updateText(newText)
        }
        editorViewController.onSelectionChanged = { [weak self] change in
            (self?.document as? ContextureDocument)?.publishSelection(change)
        }
        editorViewController.onPreviewSelectionUnmappable = { [weak self] reason in
            self?.setPreviewUnmappableReason(reason)
        }
        editorViewController.onPreviewSelectionMappable = { [weak self] in
            self?.setPreviewUnmappableReason(nil)
        }
        editorViewController.onDocumentTitleChanged = { [weak self] title in
            self?.setFrontMatterTitle(title)
        }
        viewModeAccessory.onModeSelected = { [weak self] mode in
            self?.setViewMode(mode)
        }
        if let contextureDocument = document as? ContextureDocument {
            editorViewController.documentURLProvider = { [weak contextureDocument] in
                contextureDocument?.fileURL
            }
            editorViewController.load(initialText: contextureDocument.text, format: contextureDocument.format)
            let armedIndicator = ArmedIndicatorViewController(
                documentID: contextureDocument.documentID,
                bridgeServer: AppServices.bridgeServer
            )
            window?.addTitlebarAccessoryViewController(armedIndicator)
            window?.addTitlebarAccessoryViewController(viewModeAccessory)
        }
    }

    var currentViewMode: ViewMode {
        editorViewController.currentViewMode
    }

    func setViewMode(_ mode: ViewMode) {
        editorViewController.setViewMode(mode)
        viewModeAccessory.updateSelectedMode(mode)
    }

    @objc func selectPreviewOnlyViewMode(_ sender: Any?) {
        setViewMode(.previewOnly)
    }

    @objc func selectSplitViewMode(_ sender: Any?) {
        setViewMode(.split)
    }

    @objc func toggleViewMode(_ sender: Any?) {
        let nextMode: ViewMode = currentViewMode == .previewOnly ? .split : .previewOnly
        setViewMode(nextMode)
    }

    /// Pushes text into the editor surface without marking the Document
    /// dirty — used when the file on disk changed underneath a clean
    /// buffer (issue #7).
    func reloadContent(_ text: String) {
        let format = (document as? ContextureDocument)?.format ?? .markdown
        editorViewController.load(initialText: text, format: format)
        setPreviewUnmappableReason(nil)
    }

    /// A Document with no path cannot publish a Selection Snapshot at all
    /// (ADR-0003: publishing flushes to disk first). `nil` clears the
    /// reason once the Document has somewhere to flush to. Surfaced as the
    /// window's subtitle — separate from whatever Armed-selection indicator
    /// issue #6 adds, since this reflects "can this Document share at all,"
    /// not "is a Selection Armed right now."
    func setCannotShareReason(_ reason: String?) {
        cannotShareReason = reason
        updateSubtitle()
    }

    /// When a gesture in the Preview pane cannot be mapped to a complete
    /// Source block (e.g. malformed or incomplete HTML markup), explain to the
    /// user via the window subtitle to select in Source.
    func setPreviewUnmappableReason(_ reason: String?) {
        previewUnmappableReason = reason
        updateSubtitle()
    }

    private func updateSubtitle() {
        if let previewUnmappableReason {
            window?.subtitle = previewUnmappableReason
        } else if let cannotShareReason {
            window?.subtitle = cannotShareReason
        } else {
            window?.subtitle = ""
        }
    }

    var currentZoomFactor: Double {
        editorViewController.currentZoomFactor
    }

    @objc func zoomIn(_ sender: Any?) {
        editorViewController.zoomIn()
    }

    @objc func zoomOut(_ sender: Any?) {
        editorViewController.zoomOut()
    }

    @objc func actualSize(_ sender: Any?) {
        editorViewController.actualSize()
    }
}

extension EditorWindowController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(selectPreviewOnlyViewMode(_:)):
            menuItem.state = currentViewMode == .previewOnly ? .on : .off
            return true
        case #selector(selectSplitViewMode(_:)):
            menuItem.state = currentViewMode == .split ? .on : .off
            return true
        case #selector(toggleViewMode(_:)):
            return true
        case #selector(zoomIn(_:)):
            return currentZoomFactor < DocumentZoom.maximumFactor - DocumentZoom.tolerance
        case #selector(zoomOut(_:)):
            return currentZoomFactor > DocumentZoom.minimumFactor + DocumentZoom.tolerance
        case #selector(actualSize(_:)):
            return abs(currentZoomFactor - DocumentZoom.defaultFactor) > DocumentZoom.tolerance
        default:
            return true
        }
    }
}

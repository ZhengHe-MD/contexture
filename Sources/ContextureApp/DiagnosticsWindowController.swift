import AppKit
import BridgeClient

/// Adapter Diagnostics (issue #12): per-host status ("Deterministic" /
/// "Best Effort" / "Not Installed", never flattened into one supported
/// badge — docs/product.md "Distribution direction") plus a content-free
/// recent-activity log. Shown only on explicit request (a menu item, see
/// AppDelegate's `showAdapterDiagnostics(_:)`), and always recomputed at
/// that moment rather than kept live in the background — there is nothing
/// here worth polling for.
final class DiagnosticsWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Adapter Diagnostics"
        window.center()
        self.init(window: window)
        window.contentViewController = DiagnosticsViewController()
    }

    override func showWindow(_ sender: Any?) {
        (contentViewController as? DiagnosticsViewController)?.refresh()
        super.showWindow(sender)
    }
}

final class DiagnosticsViewController: NSViewController {
    private let textView = NSTextView()

    override func loadView() {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]

        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false

        scrollView.documentView = textView
        view = scrollView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        refresh()
    }

    func refresh() {
        let adapters = KnownAdapters.descriptors().map { descriptor in
            (name: descriptor.name, compatibility: KnownAdapters.compatibility(for: descriptor))
        }
        let recentActivity = AdapterDiagnosticsLog.recentEntries()
        textView.string = DiagnosticsReportBuilder.build(adapters: adapters, recentActivity: recentActivity)
    }
}

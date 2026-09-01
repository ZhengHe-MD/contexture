import AppKit
import ContextureKit
import SelectionBridge

/// A persistent, live-updating count of this Document's Armed Selection
/// Snapshots (docs/product.md "Arming": "Because a snapshot can be Armed
/// with nothing visibly highlighted, the window shows a persistent count of
/// Armed snapshots"). At most one Snapshot is Armed per Document today, so
/// this only ever reads 0 or 1, but it is written against `isArmed` rather
/// than hard-coding that assumption.
///
/// Deliberately a titlebar accessory rather than a view inside the content
/// area: docs/product.md "Writing experience" requires the Source/Preview
/// split to run full height with a divider that reaches the top of the
/// content area, so nothing here may claim space from that split.
final class ArmedIndicatorViewController: NSTitlebarAccessoryViewController {
    private let label = NSTextField(labelWithString: "")
    private let documentID: DocumentID
    private let bridgeServer: SelectionBridgeServer
    private var observerToken: ArmedChangeObserverToken?

    init(documentID: DocumentID, bridgeServer: SelectionBridgeServer) {
        self.documentID = documentID
        self.bridgeServer = bridgeServer
        super.init(nibName: nil, bundle: nil)
        layoutAttribute = .right
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        view = label
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        refresh()
        // SelectionStore has no observation API of its own (see
        // SelectionBridgeServer's doc comment) — this refreshes on every
        // Bridge mutation regardless of which Document it was for, and
        // just re-checks its own. Mutations can arrive from a background
        // thread (an Adapter's socket request), so this always hops back
        // to the main queue before touching the label.
        observerToken = bridgeServer.addArmedChangeObserver { [weak self] in
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
    }

    deinit {
        if let observerToken {
            bridgeServer.removeArmedChangeObserver(observerToken)
        }
    }

    private func refresh() {
        label.stringValue = bridgeServer.isArmed(documentID: documentID) ? "Armed: 1" : "Armed: 0"
    }
}

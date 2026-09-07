import AppKit
import ContextureKit

/// A titlebar accessory providing one-click switching between Preview Only and Split View.
final class ViewModeAccessoryViewController: NSTitlebarAccessoryViewController {
    private let segmentedControl: NSSegmentedControl
    var onModeSelected: ((ViewMode) -> Void)?

    init(initialMode: ViewMode = .previewOnly) {
        let eyeImage = NSImage(
            systemSymbolName: "eye",
            accessibilityDescription: "Preview Only"
        )
        let splitImage = NSImage(
            systemSymbolName: "rectangle.split.2x1",
            accessibilityDescription: "Split View"
        )
        self.segmentedControl = NSSegmentedControl(
            images: [eyeImage ?? NSImage(), splitImage ?? NSImage()],
            trackingMode: .selectOne,
            target: nil,
            action: nil
        )
        super.init(nibName: nil, bundle: nil)
        layoutAttribute = .right
        updateSelectedMode(initialMode)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        segmentedControl.target = self
        segmentedControl.action = #selector(segmentChanged(_:))
        segmentedControl.setToolTip("Preview Only (⌘1)", forSegment: 0)
        segmentedControl.setToolTip("Split View (⌘2)", forSegment: 1)
        view = segmentedControl
    }

    func updateSelectedMode(_ mode: ViewMode) {
        let targetSegment = mode == .previewOnly ? 0 : 1
        if segmentedControl.selectedSegment != targetSegment {
            segmentedControl.selectedSegment = targetSegment
        }
    }

    @objc private func segmentChanged(_ sender: NSSegmentedControl) {
        let mode: ViewMode = sender.selectedSegment == 0 ? .previewOnly : .split
        onModeSelected?(mode)
    }
}

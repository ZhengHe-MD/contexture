import AppKit

/// An ephemeral pill overlay displaying the current Document magnification percentage.
/// Floats above the window content area without interfering with layout or mouse events.
final class ZoomIndicatorHUDView: NSVisualEffectView {
    private let label: NSTextField
    private var hideTimer: Timer?

    override init(frame frameRect: NSRect) {
        self.label = NSTextField(labelWithString: "")
        super.init(frame: frameRect)
        setupView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        hideTimer?.invalidate()
    }

    private func setupView() {
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.masksToBounds = true
        alphaValue = 0.0

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .center

        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    /// Pass through all mouse events so the HUD overlay never interferes with
    /// clicking, selecting, or scrolling the editor or preview underneath.
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    /// Displays the given magnification percentage and begins the fade-out timer.
    func show(percentage: String) {
        hideTimer?.invalidate()
        label.stringValue = percentage

        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0.1
        animator().alphaValue = 1.0
        NSAnimationContext.endGrouping()

        hideTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                self.animator().alphaValue = 0.0
            }
        }
    }
}

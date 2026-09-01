import AppKit

// `@main` rather than a `main.swift` script: SwiftPM's testable-executables
// support (SE-0303) links this target's sources into the test bundle too,
// and a script-style main.swift would run `app.run()` — and block forever —
// the moment the test binary starts. `@main` only executes when this target
// is built as the top-level executable product.
@main
enum ContextureMain {
    static func main() {
        // Must be created before anything touches
        // `NSDocumentController.shared`, so that shared instance is our
        // subclass rather than a plain NSDocumentController AppKit would
        // otherwise lazily create.
        _ = AppDocumentController()

        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

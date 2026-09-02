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

        // Best-effort: an unreachable-to-start Bridge (e.g. a permissions
        // problem in ~/Library/Application Support) must not stop
        // Contexture from being a complete editor on its own — it just
        // means no Selection reaches any Agent Host until the app is
        // relaunched or the underlying problem is fixed. Issue #12 is where
        // this failure becomes something the writer can actually see.
        try? AppServices.bridgeServer.start()

        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

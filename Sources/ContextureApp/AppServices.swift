import SelectionBridge

/// The app hosts exactly one Selection Bridge for its whole lifetime — one
/// running Contexture instance, one Bridge, per docs/architecture/
/// selection-bridge.md. NSDocumentController-driven document instantiation
/// doesn't leave a natural place to inject this via initializers, so it's
/// exposed the same pragmatic way as `AppDocumentController`'s document-type
/// mapping: a single shared instance.
enum AppServices {
    static let bridgeServer = SelectionBridgeServer()
}

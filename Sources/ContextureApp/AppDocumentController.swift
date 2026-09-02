import AppKit

/// Keeps the standard File > Open / New / Save machinery working without
/// depending on an app-bundle Info.plist being present (useful for
/// `swift run`, and harmless once a packaged .app supplies
/// CFBundleDocumentTypes too). The actual extension-to-class mapping lives
/// in `DocumentTypeRegistry`, which is unit-testable on its own —
/// `NSDocumentController` enforces a single shared instance app-wide, so
/// this class itself is not.
final class AppDocumentController: NSDocumentController {
    private let registry = DocumentTypeRegistry()

    override var defaultType: String? { registry.defaultExtension }

    override func typeForContents(of url: URL) throws -> String {
        url.pathExtension.lowercased()
    }

    override func documentClass(forType typeName: String) -> AnyClass? {
        registry.documentClass(forExtension: typeName)
    }
}

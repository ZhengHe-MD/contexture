import Foundation
import Testing
@testable import ContextureKit

@Suite struct ViewModeTests {
    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "ContextureKit.ViewModeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func viewModeHasExpectedRawValues() {
        #expect(ViewMode.previewOnly.rawValue == "previewOnly")
        #expect(ViewMode.split.rawValue == "split")
    }

    @Test func viewModeDefaultsToPreviewOnly() {
        let defaults = makeIsolatedDefaults()
        #expect(ViewMode.preferred(in: defaults) == .previewOnly)
    }

    @Test func viewModePersistsUserDefault() {
        let defaults = makeIsolatedDefaults()
        ViewMode.setPreferred(.split, in: defaults)
        #expect(ViewMode.preferred(in: defaults) == .split)
        #expect(defaults.string(forKey: ViewMode.userDefaultsKey) == "split")

        ViewMode.setPreferred(.previewOnly, in: defaults)
        #expect(ViewMode.preferred(in: defaults) == .previewOnly)
        #expect(defaults.string(forKey: ViewMode.userDefaultsKey) == "previewOnly")
    }
}

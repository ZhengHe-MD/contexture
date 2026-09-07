import Foundation
import Testing
@testable import ContextureKit

@Suite struct ViewModeTests {
    @Test func viewModeHasExpectedRawValues() {
        #expect(ViewMode.previewOnly.rawValue == "previewOnly")
        #expect(ViewMode.split.rawValue == "split")
    }

    @Test func viewModeDefaultsToPreviewOnly() {
        UserDefaults.standard.removeObject(forKey: ViewMode.userDefaultsKey)
        #expect(ViewMode.userDefault == .previewOnly)
    }

    @Test func viewModePersistsUserDefault() {
        UserDefaults.standard.removeObject(forKey: ViewMode.userDefaultsKey)
        ViewMode.userDefault = .split
        #expect(ViewMode.userDefault == .split)
        #expect(UserDefaults.standard.string(forKey: ViewMode.userDefaultsKey) == "split")

        ViewMode.userDefault = .previewOnly
        #expect(ViewMode.userDefault == .previewOnly)
        #expect(UserDefaults.standard.string(forKey: ViewMode.userDefaultsKey) == "previewOnly")

        // Cleanup
        UserDefaults.standard.removeObject(forKey: ViewMode.userDefaultsKey)
    }
}

import Foundation
import Testing
@testable import ContextureKit

@Suite struct DocumentZoomTests {
    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "ContextureKit.DocumentZoomTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func zoomLevelsAreMonotonicallyIncreasing() {
        #expect(DocumentZoom.levels.count >= 5)
        for i in 1..<DocumentZoom.levels.count {
            #expect(DocumentZoom.levels[i] > DocumentZoom.levels[i - 1])
        }
        #expect(DocumentZoom.levels.first == DocumentZoom.minimumFactor)
        #expect(DocumentZoom.levels.last == DocumentZoom.maximumFactor)
        #expect(DocumentZoom.levels.contains(DocumentZoom.defaultFactor))
    }

    @Test func zoomedInStepsToNextDiscreteLevel() {
        #expect(DocumentZoom.zoomedIn(from: 1.0) == 1.15)
        #expect(DocumentZoom.zoomedIn(from: 1.15) == 1.25)
        #expect(DocumentZoom.zoomedIn(from: 1.25) == 1.50)
        #expect(DocumentZoom.zoomedIn(from: 0.50) == 0.75)
        #expect(DocumentZoom.zoomedIn(from: 2.50) == 3.00)
        #expect(DocumentZoom.zoomedIn(from: 3.00) == 3.00)
        #expect(DocumentZoom.zoomedIn(from: 3.50) == 3.00)

        // Intermediate values step to the next higher level
        #expect(DocumentZoom.zoomedIn(from: 1.05) == 1.15)
        #expect(DocumentZoom.zoomedIn(from: 0.80) == 0.85)
    }

    @Test func zoomedOutStepsToPreviousDiscreteLevel() {
        #expect(DocumentZoom.zoomedOut(from: 1.0) == 0.85)
        #expect(DocumentZoom.zoomedOut(from: 0.85) == 0.75)
        #expect(DocumentZoom.zoomedOut(from: 0.75) == 0.50)
        #expect(DocumentZoom.zoomedOut(from: 0.50) == 0.50)
        #expect(DocumentZoom.zoomedOut(from: 0.40) == 0.50)
        #expect(DocumentZoom.zoomedOut(from: 3.00) == 2.50)

        // Intermediate values step to the next lower level
        #expect(DocumentZoom.zoomedOut(from: 1.10) == 1.00)
        #expect(DocumentZoom.zoomedOut(from: 1.20) == 1.15)
    }

    @Test func clampRestrictsToBounds() {
        #expect(DocumentZoom.clamp(0.1) == 0.50)
        #expect(DocumentZoom.clamp(1.25) == 1.25)
        #expect(DocumentZoom.clamp(4.0) == 3.00)
    }

    @Test func percentageStringFormatsCorrectly() {
        #expect(DocumentZoom.percentageString(for: 1.00) == "100%")
        #expect(DocumentZoom.percentageString(for: 1.15) == "115%")
        #expect(DocumentZoom.percentageString(for: 1.25) == "125%")
        #expect(DocumentZoom.percentageString(for: 0.50) == "50%")
        #expect(DocumentZoom.percentageString(for: 0.85) == "85%")
        #expect(DocumentZoom.percentageString(for: 3.00) == "300%")
    }

    @Test func preferredZoomDefaultsToOneHundredPercent() {
        let defaults = makeIsolatedDefaults()
        #expect(DocumentZoom.preferred(in: defaults) == 1.00)
    }

    @Test func preferredZoomPersistsUserDefault() {
        let defaults = makeIsolatedDefaults()
        DocumentZoom.setPreferred(1.25, in: defaults)
        #expect(DocumentZoom.preferred(in: defaults) == 1.25)

        DocumentZoom.setPreferred(0.75, in: defaults)
        #expect(DocumentZoom.preferred(in: defaults) == 0.75)
    }

    @Test func invalidStoredZoomFallsBackToDefault() {
        let defaults = makeIsolatedDefaults()
        defaults.set(10.0, forKey: DocumentZoom.userDefaultsKey)
        #expect(DocumentZoom.preferred(in: defaults) == 1.00)

        defaults.set(0.1, forKey: DocumentZoom.userDefaultsKey)
        #expect(DocumentZoom.preferred(in: defaults) == 1.00)
    }
}

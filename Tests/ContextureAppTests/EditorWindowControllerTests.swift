import AppKit
import Testing
@testable import ContextureApp

@Suite struct EditorWindowControllerTests {
    @Test func defaultSizeUsesTwoThirdsOfTheVisibleScreen() {
        let size = EditorWindowController.defaultContentSize(
            for: NSSize(width: 1_512, height: 945)
        )

        #expect(size == NSSize(width: 1_008, height: 630))
    }

    @Test func defaultSizeRoundsUpToRemainAtLeastTwoThirds() {
        let size = EditorWindowController.defaultContentSize(
            for: NSSize(width: 1_001, height: 801)
        )

        #expect(size == NSSize(width: 668, height: 534))
    }

    @Test func defaultSizePreservesTheMinimumUsableContentSize() {
        let size = EditorWindowController.defaultContentSize(
            for: NSSize(width: 600, height: 300)
        )

        #expect(size == EditorWindowController.minimumContentSize)
    }

    @Test func defaultSizeHasAStableFallbackWhenNoScreenIsAvailable() {
        let size = EditorWindowController.defaultContentSize(for: nil)

        #expect(size == NSSize(width: 1_200, height: 800))
    }

    @Test func frontMatterTitleOverridesTheDocumentFilename() {
        #expect(
            EditorWindowController.windowTitle(
                frontMatterTitle: "A Writer's Page",
                documentDisplayName: "draft.md"
            ) == "A Writer's Page"
        )
    }

    @Test func missingOrBlankFrontMatterTitleFallsBackToTheDocumentFilename() {
        for title in [nil, "", "   "] as [String?] {
            #expect(
                EditorWindowController.windowTitle(
                    frontMatterTitle: title,
                    documentDisplayName: "draft.md"
                ) == "draft.md"
            )
        }
    }
}

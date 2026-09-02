import AppKit
import Testing
@testable import ContextureApp

@Suite struct EditorWindowControllerTests {
    @Test @MainActor func repeatedLegacyMinimumFramesExpandDuringInitialPresentation() throws {
        let document = MarkdownDocument()
        let controller = EditorWindowController(frameAutosaveName: nil)
        document.addWindowController(controller)
        controller.windowDidLoad()
        controller.window?.setContentSize(EditorWindowController.minimumContentSize)
        controller.windowDidResize(Notification(
            name: NSWindow.didResizeNotification,
            object: controller.window
        ))
        defer {
            document.removeWindowController(controller)
            controller.close()
        }

        let actual = try #require(controller.window?.contentView?.frame.size)
        let screen = try #require(controller.window?.screen?.visibleFrame.size)

        #expect(actual.width * actual.height >= screen.width * screen.height * 2.0 / 3.0)

        // AppKit can apply the autosaved window frame and then the Document
        // restoration frame as two separate initial resizes.
        controller.window?.setContentSize(EditorWindowController.minimumContentSize)
        controller.windowDidResize(Notification(
            name: NSWindow.didResizeNotification,
            object: controller.window
        ))
        let afterSecondRestore = try #require(controller.window?.contentView?.frame.size)

        #expect(
            afterSecondRestore.width * afterSecondRestore.height
                >= screen.width * screen.height * 2.0 / 3.0
        )
    }

    @Test @MainActor func userCanResizeToMinimumAfterInitialPresentation() throws {
        let document = MarkdownDocument()
        let controller = EditorWindowController(frameAutosaveName: nil)
        document.addWindowController(controller)
        controller.windowDidLoad()
        controller.windowDidBecomeKey(Notification(
            name: NSWindow.didBecomeKeyNotification,
            object: controller.window
        ))
        controller.window?.setContentSize(EditorWindowController.minimumContentSize)
        controller.windowDidResize(Notification(
            name: NSWindow.didResizeNotification,
            object: controller.window
        ))
        defer {
            document.removeWindowController(controller)
            controller.close()
        }

        let actual = try #require(controller.window?.contentView?.frame.size)

        #expect(actual == EditorWindowController.minimumContentSize)
    }

    @Test func defaultSizePreservesScreenShapeWhileCoveringTwoThirdsOfItsArea() {
        let size = EditorWindowController.defaultContentSize(
            for: NSSize(width: 1_512, height: 945)
        )

        #expect(size == NSSize(width: 1_235, height: 772))
    }

    @Test func defaultSizeOccupiesAtLeastTwoThirdsOfTheVisibleScreenArea() {
        let screen = NSSize(width: 1_512, height: 945)
        let size = EditorWindowController.defaultContentSize(for: screen)

        #expect(size.width * size.height >= screen.width * screen.height * 2.0 / 3.0)
    }

    @Test func defaultSizeRoundsUpToRemainAtLeastTwoThirdsByArea() {
        let size = EditorWindowController.defaultContentSize(
            for: NSSize(width: 1_001, height: 801)
        )

        #expect(size == NSSize(width: 818, height: 655))
    }

    @Test func defaultSizePreservesTheMinimumUsableContentSize() {
        let size = EditorWindowController.defaultContentSize(
            for: NSSize(width: 500, height: 300)
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

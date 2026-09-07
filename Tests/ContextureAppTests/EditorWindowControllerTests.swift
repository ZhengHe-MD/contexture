import AppKit
import ContextureKit
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

    @Test @MainActor func viewModeActionsSwitchAndValidateMenuItems() throws {
        let suiteName = "ContextureApp.EditorWindowControllerTests.\(UUID().uuidString)"
        let isolatedDefaults = UserDefaults(suiteName: suiteName)!
        isolatedDefaults.removePersistentDomain(forName: suiteName)

        let document = MarkdownDocument()
        let controller = EditorWindowController(
            frameAutosaveName: nil,
            userDefaults: isolatedDefaults
        )
        document.addWindowController(controller)
        controller.windowDidLoad()
        defer {
            document.removeWindowController(controller)
            controller.close()
            isolatedDefaults.removePersistentDomain(forName: suiteName)
        }

        #expect(controller.currentViewMode == .previewOnly)

        let previewItem = NSMenuItem(title: "Preview Only", action: #selector(EditorWindowController.selectPreviewOnlyViewMode(_:)), keyEquivalent: "")
        let splitItem = NSMenuItem(title: "Split View", action: #selector(EditorWindowController.selectSplitViewMode(_:)), keyEquivalent: "")
        let toggleItem = NSMenuItem(title: "Toggle View Mode", action: #selector(EditorWindowController.toggleViewMode(_:)), keyEquivalent: "")

        #expect(controller.validateMenuItem(previewItem))
        #expect(previewItem.state == .on)
        #expect(controller.validateMenuItem(splitItem))
        #expect(splitItem.state == .off)
        #expect(controller.validateMenuItem(toggleItem))

        controller.selectSplitViewMode(nil)
        #expect(controller.currentViewMode == .split)
        #expect(ViewMode.preferred(in: isolatedDefaults) == .split)

        _ = controller.validateMenuItem(previewItem)
        _ = controller.validateMenuItem(splitItem)
        #expect(previewItem.state == .off)
        #expect(splitItem.state == .on)

        controller.toggleViewMode(nil)
        #expect(controller.currentViewMode == .previewOnly)
        #expect(ViewMode.preferred(in: isolatedDefaults) == .previewOnly)

        _ = controller.validateMenuItem(previewItem)
        _ = controller.validateMenuItem(splitItem)
        #expect(previewItem.state == .on)
        #expect(splitItem.state == .off)
    }
}


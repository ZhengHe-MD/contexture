import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Diagnostics is an app-level concern, not tied to any one Document's
    // window — one shared window, created lazily and reused across opens,
    // rather than one per Document the way EditorWindowController is.
    private lazy var diagnosticsWindowController = DiagnosticsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = AppMenuBuilder.makeMainMenu()
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @objc func showAdapterDiagnostics(_ sender: Any?) {
        diagnosticsWindowController.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Builds the menu bar by hand: there is no Storyboard/XIB in this package,
/// and the standard NSDocument action selectors (`newDocument:`,
/// `openDocument:`, `saveDocument:`, `saveDocumentAs:`,
/// `revertDocumentToSaved:`) are already implemented by
/// `NSDocumentController`/`NSDocument` via the responder chain — items only
/// need the right selector and `nil` target.
enum AppMenuBuilder {
    static func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit Contexture", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu
        fileMenu.addItem(withTitle: "New", action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "Open…", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenu.addItem(withTitle: "Save", action: #selector(NSDocument.save(_:)), keyEquivalent: "s")
        let saveAs = fileMenu.addItem(
            withTitle: "Save As…",
            action: #selector(NSDocument.saveAs(_:)),
            keyEquivalent: "s"
        )
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(
            withTitle: "Revert to Saved",
            action: #selector(NSDocument.revertToSaved(_:)),
            keyEquivalent: ""
        )

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let sharingMenuItem = NSMenuItem()
        mainMenu.addItem(sharingMenuItem)
        let sharingMenu = NSMenu(title: "Sharing")
        sharingMenuItem.submenu = sharingMenu
        // Off / Next Prompt are mutually exclusive (docs/product.md
        // "Sharing modes"); MarkdownDocument.validateMenuItem(_:) is what
        // actually checks the currently-active one. These dispatch through
        // the responder chain to the key window's document exactly like
        // the File menu's NSDocument actions do — see this enum's doc
        // comment — except these selectors are defined on MarkdownDocument
        // itself rather than being AppKit-standard ones.
        sharingMenu.addItem(
            withTitle: "Off",
            action: #selector(MarkdownDocument.setSharingModeOff(_:)),
            keyEquivalent: ""
        )
        sharingMenu.addItem(
            withTitle: "Next Prompt",
            action: #selector(MarkdownDocument.setSharingModeNextPrompt(_:)),
            keyEquivalent: ""
        )
        sharingMenu.addItem(NSMenuItem.separator())
        // The "single-key clear" the persistent Armed indicator promises
        // (docs/product.md "Arming"). Command-Period rather than a bare
        // Escape: Escape is CodeMirror's own key for dismissing its search
        // panel/autocomplete inside the Source pane's WKWebView, and a
        // window's performKeyEquivalent walks the view hierarchy before
        // falling through to the menu, so a plain Escape could be consumed
        // there before it ever reaches this item. Command-Period is
        // macOS's long-standing "cancel/stop" shortcut, semantically close
        // to "clear," and unclaimed by anything else in this menu bar.
        let clearItem = sharingMenu.addItem(
            withTitle: "Clear Armed Snapshot",
            action: #selector(MarkdownDocument.clearArmedSnapshot(_:)),
            keyEquivalent: "."
        )
        clearItem.keyEquivalentModifierMask = [.command]
        sharingMenu.addItem(NSMenuItem.separator())
        // Unlike the items above, this isn't Document-scoped, so it can't
        // use the nil-target responder-chain pattern the way those do —
        // AppDelegate isn't itself part of the responder chain. NSApp.delegate
        // is already set by the time this menu is built (AppMain.swift sets
        // it before app.run(), and this only ever runs from
        // applicationDidFinishLaunching).
        sharingMenu.addItem(
            withTitle: "Adapter Diagnostics…",
            action: #selector(AppDelegate.showAdapterDiagnostics(_:)),
            keyEquivalent: ""
        ).target = NSApp.delegate

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        NSApp.windowsMenu = windowMenu

        return mainMenu
    }
}

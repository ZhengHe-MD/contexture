import AppKit
import ContextureKit

/// A Document (CONTEXT.md) backed by a local Markdown file. This is the
/// only Document type today, but nothing here is welded to Markdown
/// specifically: `AppDocumentController` is what maps a file extension to a
/// Document subclass, so a second format registers a second mapping rather
/// than changing this class or its NSDocument plumbing.
final class MarkdownDocument: NSDocument {
    let documentID = DocumentID()
    private let sourceWindowID = SourceWindowID()
    private var selectionVersion = 0

    private(set) var text: String = ""

    /// Writer-controlled lifetime of Selection Context for this Document
    /// (docs/product.md "Sharing modes"). Next Prompt is the product
    /// default. Pinned is out of scope (docs/product.md), so this is not
    /// exposed as anything richer than the two-case `SharingMode` it wraps.
    /// Persists on this Document instance across selections — it is not
    /// reset by any individual Selection.
    private(set) var sharingMode: SharingMode = .nextPrompt

    override class var autosavesInPlace: Bool { true }

    /// Not yet the true Working-Root-relative path the architecture doc
    /// calls for — that needs a caller-supplied Working Root to compute
    /// against, which arrives with issue #8's scoping. Using just the
    /// filename here is a safe, deliberately conservative placeholder: it
    /// never leaks an absolute path (ADR-0004), the one hard invariant
    /// that must hold regardless.
    private var relativePathForSharing: String {
        fileURL?.lastPathComponent ?? displayName ?? "Untitled"
    }

    /// Selecting is sharing — there is no separate share gesture
    /// (docs/product.md "Arming"). Called for every non-empty Selection the
    /// editor reports; a collapse to an empty range is never reported (see
    /// editor-web/src/main.js), so Arming naturally survives it.
    ///
    /// Off means no Selection Context is made available at all
    /// (docs/product.md "Sharing modes") — the simplest way to guarantee
    /// that is to never Arm anything in the first place rather than Arm and
    /// filter later.
    func publishSelection(_ change: EditorSelectionChange) {
        guard sharingMode != .off else { return }
        selectionVersion += 1
        let snapshot = SelectionSnapshot(
            documentID: documentID,
            sourceBytes: Data(change.text.utf8),
            format: .markdown,
            relativePath: relativePathForSharing,
            revision: RevisionHash(contentBytes: Data(text.utf8)),
            byteRange: SourceByteRange(lowerBound: change.byteStart, upperBound: change.byteEnd),
            displayLine: change.line,
            displayColumn: change.column,
            sharingMode: sharingMode,
            createdAt: Date(),
            sourceWindow: sourceWindowID,
            version: selectionVersion
        )
        AppServices.bridgeServer.publish(snapshot)
    }

    /// Changes this Document's Sharing Mode (docs/product.md "Sharing
    /// modes"). Switching to Off also clears whatever is currently Armed
    /// for this Document — "no Selection Context is made available at all"
    /// must hold immediately, not just for the next Selection. Switching
    /// away from Off never retroactively Arms anything: selecting is
    /// sharing, so only a new Selection Arms a Snapshot.
    func setSharingMode(_ mode: SharingMode) {
        guard mode != sharingMode else { return }
        sharingMode = mode
        if mode == .off {
            AppServices.bridgeServer.clear(documentID: documentID)
        }
    }

    override func makeWindowControllers() {
        let controller = EditorWindowController()
        addWindowController(controller)
        // Not invoked automatically: this window is built in code rather
        // than loaded from a NIB. See EditorWindowController.windowDidLoad.
        controller.windowDidLoad()
    }

    override func read(from data: Data, ofType typeName: String) throws {
        guard let decoded = String(data: data, encoding: .utf8) else {
            throw NSError(
                domain: "Contexture",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "\(String(describing: displayName)) is not valid UTF-8 text."]
            )
        }
        text = decoded
    }

    override func data(ofType typeName: String) throws -> Data {
        Data(text.utf8)
    }

    /// Applied on every editor keystroke so the window's dirty state tracks
    /// the writer's live edits, independent of when save actually happens.
    func updateText(_ newText: String) {
        guard newText != text else { return }
        text = newText
        updateChangeCount(.changeDone)
        // An edit invalidates whatever was Armed for this Document by
        // revision mismatch (docs/architecture/selection-bridge.md
        // "Lifecycle and deduplication") — the writer typed, so the old
        // Snapshot's content is stale, full stop. Clearing here proactively
        // is simpler than comparing revision hashes at read time, and
        // leaves that machinery (flush-on-publish, external-write
        // reconciliation) to issue #7.
        AppServices.bridgeServer.clear(documentID: documentID)
    }

    /// Reads the live editor surface before writing, so save never races an
    /// in-flight keystroke that hasn't yet reached `text` via
    /// `updateText(_:)`.
    override func save(
        to url: URL,
        ofType typeName: String,
        for saveOperation: NSDocument.SaveOperationType,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let windowController = windowControllers.first as? EditorWindowController else {
            super.save(to: url, ofType: typeName, for: saveOperation, completionHandler: completionHandler)
            return
        }
        // Swift does not allow an explicit `self` capture here (it would
        // make the `super.save` dispatch below ambiguous), so this closure
        // relies on the implicit strong capture — acceptable for a one-shot
        // completion handler that fires and is released immediately after.
        windowController.currentEditorContent { latest in
            if let latest {
                self.text = latest
            }
            super.save(to: url, ofType: typeName, for: saveOperation, completionHandler: completionHandler)
        }
    }

    /// Closing a Document is one of the ways its Selection Snapshot stops
    /// being Armed (docs/architecture/selection-bridge.md "Lifecycle and
    /// deduplication") — once the window is gone, nothing else would ever
    /// supersede or clear it.
    override func close() {
        clearArmedSnapshotForClose()
        super.close()
    }

    /// The clearing half of `close()`, pulled out as its own internal
    /// method so it is exercisable directly from a unit test. Calling the
    /// real `NSDocument.close()` from a headless test touches
    /// `NSDocumentController.shared` (creating a plain base-class instance
    /// the first time anything does) and, for a dirty Document, can
    /// synchronously prompt a save-changes panel — both are unsafe to rely
    /// on outside a running app. See also `AppDocumentControllerTests.swift`
    /// for the same concern around `NSDocumentController` subclasses.
    func clearArmedSnapshotForClose() {
        AppServices.bridgeServer.clear(documentID: documentID)
    }

    // MARK: Sharing Mode menu actions

    /// Wired from `AppMenuBuilder`'s Sharing menu with a `nil` target, the
    /// same responder-chain pattern the File menu's `NSDocument` actions
    /// already use — see that enum's doc comment.
    @objc func setSharingModeOff(_ sender: Any?) {
        setSharingMode(.off)
    }

    @objc func setSharingModeNextPrompt(_ sender: Any?) {
        setSharingMode(.nextPrompt)
    }

    /// The "single-key clear" the persistent Armed indicator promises
    /// (docs/product.md "Arming") — same clear path as an edit or a close.
    @objc func clearArmedSnapshot(_ sender: Any?) {
        AppServices.bridgeServer.clear(documentID: documentID)
    }
}

extension MarkdownDocument {
    /// Adds checkmark state for the Sharing menu's mutually exclusive
    /// Off/Next Prompt pair. `NSDocument` already conforms to
    /// `NSMenuItemValidation` and uses this to drive its own standard items
    /// (Save, Revert, …), so any other action falls through to `super` to
    /// preserve that existing behavior (e.g. disabling Save when unedited).
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(setSharingModeOff(_:)):
            menuItem.state = sharingMode == .off ? .on : .off
            return true
        case #selector(setSharingModeNextPrompt(_:)):
            menuItem.state = sharingMode == .nextPrompt ? .on : .off
            return true
        case #selector(clearArmedSnapshot(_:)):
            return true
        default:
            return super.validateMenuItem(menuItem)
        }
    }
}

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
    /// Bumped on every Selection *and* every edit, so a publish in flight
    /// (it flushes to disk first, which is async) can tell whether it is
    /// still the most recent thing that happened to this Document by the
    /// time the flush completes — see `publishSelection(_:)`.
    private var stateVersion = 0

    /// The on-disk content hash as of the last read, flush, or detected
    /// external change. Used to tell "the file watcher fired because we
    /// just wrote it ourselves" apart from a genuine external write.
    private var lastKnownDiskRevision: RevisionHash?
    private var fileWatcher: FileWatcher?

    private(set) var text: String = ""

    /// Writer-controlled lifetime of Selection Context for this Document
    /// (docs/product.md "Sharing modes"). Next Prompt is the product
    /// default. Pinned is out of scope (docs/product.md), so this is not
    /// exposed as anything richer than the two-case `SharingMode` it wraps.
    /// Persists on this Document instance across selections — it is not
    /// reset by any individual Selection.
    private(set) var sharingMode: SharingMode = .nextPrompt

    override class var autosavesInPlace: Bool { true }

    /// A publish-time placeholder, not the real Working-Root-relative path:
    /// that needs a caller-supplied Working Root, which only exists at read
    /// time (issue #8 — see `WorkingRootScope`, which overwrites this
    /// field on every `read()`). Kept as just the filename here rather than
    /// anything richer so that a Snapshot read without going through that
    /// scoping (there is no such path today, but nothing enforces that
    /// statically) still never leaks an absolute path — ADR-0004's one hard
    /// invariant that must hold regardless.
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
    /// filter later, so this returns before even looking at `fileURL`.
    ///
    /// ADR-0003: publishing flushes the buffer to disk *before* the
    /// Snapshot becomes Armed, so its revision hash always describes actual
    /// on-disk content. A Document with no path has nowhere to flush to and
    /// cannot publish at all — `EditorWindowController` is told so it can
    /// show that rather than let the Document appear Armed.
    func publishSelection(_ change: EditorSelectionChange) {
        guard sharingMode != .off else { return }

        guard let fileURL, let fileType else {
            editorWindowController?.setCannotShareReason("Save this document to share a Selection.")
            return
        }
        editorWindowController?.setCannotShareReason(nil)

        stateVersion += 1
        let capturedVersion = stateVersion

        func armFromCurrentDisk() {
            // A newer Selection or edit arrived while the flush below was
            // in flight — that one either already Armed something more
            // current, or (if it was an edit) invalidated Arming outright.
            // Either way this now-stale attempt must not overwrite it.
            guard capturedVersion == self.stateVersion,
                  let diskBytes = try? Data(contentsOf: fileURL) else { return }
            let diskRevision = RevisionHash(contentBytes: diskBytes)
            lastKnownDiskRevision = diskRevision
            let snapshot = SelectionSnapshot(
                documentID: documentID,
                sourceBytes: Data(change.text.utf8),
                format: .markdown,
                relativePath: relativePathForSharing,
                absolutePath: fileURL.path,
                revision: diskRevision,
                byteRange: SourceByteRange(lowerBound: change.byteStart, upperBound: change.byteEnd),
                displayLine: change.line,
                displayColumn: change.column,
                sharingMode: sharingMode,
                createdAt: Date(),
                sourceWindow: sourceWindowID,
                version: capturedVersion
            )
            AppServices.bridgeServer.publish(snapshot)
        }

        // The buffer already matches disk (NSDocument's own dirty tracking)
        // — no need to rewrite a file that hasn't changed, just hash what's
        // already there.
        if isDocumentEdited {
            save(to: fileURL, ofType: fileType, for: .saveOperation) { error in
                guard error == nil else { return }
                armFromCurrentDisk()
            }
        } else {
            armFromCurrentDisk()
        }
    }

    private var editorWindowController: EditorWindowController? {
        windowControllers.first as? EditorWindowController
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
        if fileURL == nil {
            controller.setCannotShareReason("Save this document to share a Selection.")
        }
    }

    override func read(from url: URL, ofType typeName: String) throws {
        try super.read(from: url, ofType: typeName)
        lastKnownDiskRevision = RevisionHash(contentBytes: Data(text.utf8))
        watchFile(at: url)
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
    /// Also invalidates whatever was Armed for this Document: the
    /// architecture doc lists "its revision no longer matches" alongside
    /// being superseded, consumed, or explicitly cleared as ways Arming
    /// ends, and an edit is the simplest case of that — the Snapshot's
    /// revision hash necessarily no longer describes the live buffer.
    /// Clearing here proactively is simpler than comparing revision hashes
    /// at read time.
    func updateText(_ newText: String) {
        guard newText != text else { return }
        text = newText
        stateVersion += 1
        updateChangeCount(.changeDone)
        AppServices.bridgeServer.clear(documentID: documentID)
    }

    /// Keeps post-save disk state in sync for both an ordinary Save and the
    /// flush path `publishSelection(_:)` uses. The Source is already mirrored
    /// into `text` by `contentChanged` messages before WebKit returns a
    /// subsequent Command-S key event or reports a Selection, so saving must
    /// enter AppKit immediately from this override.
    ///
    /// In particular, do not put an asynchronous WebKit query before
    /// `super.save` here. `NSDocument` serializes user Save actions by waiting
    /// synchronously on the main thread. If an earlier save can only continue
    /// from a WebKit completion on that same thread, a repeated Command-S
    /// deadlocks the app.
    override func save(
        to url: URL,
        ofType typeName: String,
        for saveOperation: NSDocument.SaveOperationType,
        completionHandler: @escaping (Error?) -> Void
    ) {
        super.save(to: url, ofType: typeName, for: saveOperation) { error in
            if error == nil {
                self.lastKnownDiskRevision = RevisionHash(contentBytes: Data(self.text.utf8))
                self.watchFile(at: url)
                self.editorWindowController?.setCannotShareReason(nil)
            }
            completionHandler(error)
        }
    }

    /// Closing a Document is one of the ways its Selection Snapshot stops
    /// being Armed (docs/architecture/selection-bridge.md "Lifecycle and
    /// deduplication") — once the window is gone, nothing else would ever
    /// supersede or clear it. Also stops watching the file: nothing is left
    /// to reconcile external writes against once the Document is gone.
    override func close() {
        fileWatcher?.stop()
        fileWatcher = nil
        clearArmedSnapshotForClose()
        super.close()
    }

    /// The Arming-clearing half of `close()`, pulled out as its own
    /// internal method so it is exercisable directly from a unit test.
    /// Calling the real `NSDocument.close()` from a headless test touches
    /// `NSDocumentController.shared` (creating a plain base-class instance
    /// the first time anything does) and, for a dirty Document, can
    /// synchronously prompt a save-changes panel — both are unsafe to rely
    /// on outside a running app. See also `AppDocumentControllerTests.swift`
    /// for the same concern around `NSDocumentController` subclasses.
    func clearArmedSnapshotForClose() {
        AppServices.bridgeServer.clear(documentID: documentID)
    }

    // MARK: External writes

    /// (Re)starts watching `url` for writes from another process. Safe to
    /// call repeatedly (a fresh read, a Save As to a new location) — always
    /// tears down whatever was being watched before.
    private func watchFile(at url: URL) {
        fileWatcher?.stop()
        // FileWatcher calls back on its own background queue; document
        // state and any UI (the conflict alert) must be touched on main.
        fileWatcher = FileWatcher(url: url) { [weak self] in
            DispatchQueue.main.async {
                self?.handleExternalFileChange()
            }
        }
    }

    /// Contexture is not the authority over the live Document — Agent Hosts
    /// write files with their own tools (docs/architecture/selection-
    /// bridge.md "Persistence and Document authority"). This reconciles
    /// whatever just happened on disk with the in-memory buffer.
    private func handleExternalFileChange() {
        guard let fileURL, let diskBytes = try? Data(contentsOf: fileURL) else { return }
        let diskRevision = RevisionHash(contentBytes: diskBytes)
        // The watcher also fires for our own writes (flush, Save); this is
        // what tells that apart from a genuine external change.
        guard diskRevision != lastKnownDiskRevision else { return }

        // Whatever was Armed for this Document described content that is
        // no longer current, regardless of which branch below runs.
        stateVersion += 1
        AppServices.bridgeServer.clear(documentID: documentID)

        if isDocumentEdited {
            raiseExternalWriteConflict(diskBytes: diskBytes, diskRevision: diskRevision)
        } else {
            reloadFromDisk(bytes: diskBytes, revision: diskRevision)
        }
    }

    private func reloadFromDisk(bytes: Data, revision: RevisionHash) {
        guard let decoded = String(data: bytes, encoding: .utf8) else { return }
        text = decoded
        lastKnownDiskRevision = revision
        updateChangeCount(.changeCleared)
        editorWindowController?.reloadContent(decoded)
    }

    /// The buffer has unsaved changes and the file also changed underneath
    /// it — flushing over that write would silently discard whatever the
    /// other process wrote; reloading would silently discard the writer's
    /// own edits. Neither happens without asking.
    private func raiseExternalWriteConflict(diskBytes: Data, diskRevision: RevisionHash) {
        guard let window = editorWindowController?.window else { return }
        let alert = NSAlert()
        alert.messageText = "“\(displayName ?? "This document")” changed on disk"
        alert.informativeText =
            "Another process modified this file while you had unsaved changes here. " +
            "Keep your changes and overwrite what's on disk next time you save, or reload to see what's there now?"
        alert.addButton(withTitle: "Keep My Changes")
        alert.addButton(withTitle: "Reload from Disk")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertSecondButtonReturn else { return }
            self.reloadFromDisk(bytes: diskBytes, revision: diskRevision)
        }
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

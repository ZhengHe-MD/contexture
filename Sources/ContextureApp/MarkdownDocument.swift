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
    /// ADR-0003: publishing flushes the buffer to disk *before* the
    /// Snapshot becomes Armed, so its revision hash always describes actual
    /// on-disk content. A Document with no path has nowhere to flush to and
    /// cannot publish at all — `EditorWindowController` is told so it can
    /// show that rather than let the Document appear Armed.
    func publishSelection(_ change: EditorSelectionChange) {
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
                revision: diskRevision,
                byteRange: SourceByteRange(lowerBound: change.byteStart, upperBound: change.byteEnd),
                displayLine: change.line,
                displayColumn: change.column,
                sharingMode: .nextPrompt,
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
    func updateText(_ newText: String) {
        guard newText != text else { return }
        text = newText
        stateVersion += 1
        updateChangeCount(.changeDone)
        AppServices.bridgeServer.clear(documentID: documentID)
    }

    /// Reads the live editor surface before writing, so save never races an
    /// in-flight keystroke that hasn't yet reached `text` via
    /// `updateText(_:)`. Also the flush path `publishSelection(_:)` uses —
    /// ADR-0003 calls this a "flush", not a full interactive Save, but they
    /// are the same underlying write; reusing it keeps there being exactly
    /// one place this Document's bytes reach disk.
    override func save(
        to url: URL,
        ofType typeName: String,
        for saveOperation: NSDocument.SaveOperationType,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let windowController = editorWindowController else {
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
            super.save(to: url, ofType: typeName, for: saveOperation) { error in
                if error == nil {
                    self.lastKnownDiskRevision = RevisionHash(contentBytes: Data(self.text.utf8))
                    self.watchFile(at: url)
                    windowController.setCannotShareReason(nil)
                }
                completionHandler(error)
            }
        }
    }

    override func close() {
        fileWatcher?.stop()
        fileWatcher = nil
        super.close()
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
}

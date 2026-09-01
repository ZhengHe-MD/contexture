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
    func publishSelection(_ change: EditorSelectionChange) {
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
            sharingMode: .nextPrompt,
            createdAt: Date(),
            sourceWindow: sourceWindowID,
            version: selectionVersion
        )
        AppServices.bridgeServer.publish(snapshot)
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
}

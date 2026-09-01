import AppKit

/// A Document (CONTEXT.md) backed by a local Markdown file. This is the
/// only Document type today, but nothing here is welded to Markdown
/// specifically: `AppDocumentController` is what maps a file extension to a
/// Document subclass, so a second format registers a second mapping rather
/// than changing this class or its NSDocument plumbing.
final class MarkdownDocument: NSDocument {
    private(set) var text: String = ""

    override class var autosavesInPlace: Bool { true }

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

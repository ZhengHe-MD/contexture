import { EditorView, basicSetup } from "codemirror";
import { EditorState } from "@codemirror/state";
import { markdown } from "@codemirror/lang-markdown";
import { languages } from "@codemirror/language-data";

// Bridge protocol with the native shell (see Sources/ContextureApp/EditorBridge.swift):
//   JS -> native: window.webkit.messageHandlers.contexture.postMessage({ type, ... })
//     - { type: "ready" }
//     - { type: "contentChanged", text }
//     - { type: "selectionChanged", text, byteStart, byteEnd, line, column }
//   native -> JS: evaluateJavaScript of the window.__contexture_* functions below.
function postToNative(message) {
  if (window.webkit?.messageHandlers?.contexture) {
    window.webkit.messageHandlers.contexture.postMessage(message);
  }
}

// Content pushed in from the native side (initial load, external-file reload)
// must not itself be reported back as a writer edit or a fresh Selection.
let suppressChangeNotification = false;

const byteLength = (text) => new TextEncoder().encode(text).length;

const view = new EditorView({
  state: EditorState.create({
    doc: "",
    extensions: [
      basicSetup,
      markdown({ codeLanguages: languages }),
      EditorView.lineWrapping,
      EditorView.contentAttributes.of({
        spellcheck: "true",
        autocorrect: "on",
        autocapitalize: "sentences",
      }),
      EditorView.updateListener.of((update) => {
        if (suppressChangeNotification) return;

        // Order matters: native's cached full-document text (used to
        // compute a Selection Snapshot's revision hash) must be current
        // before it processes a selectionChanged message for the same
        // update, so contentChanged is always posted first.
        if (update.docChanged) {
          postToNative({ type: "contentChanged", text: view.state.doc.toString() });
        }

        // Selecting is sharing — there is no separate share gesture — but
        // only a non-empty range is a Selection. A collapse to an empty
        // range is deliberately NOT reported: Arming survives the visible
        // Selection collapsing (docs/product.md "Arming"), so silence here,
        // not a clear, is what keeps a previously Armed Snapshot alive.
        if (update.selectionSet) {
          const range = view.state.selection.main;
          if (!range.empty) {
            const text = view.state.sliceDoc(range.from, range.to);
            const line = view.state.doc.lineAt(range.head);
            postToNative({
              type: "selectionChanged",
              text,
              byteStart: byteLength(view.state.sliceDoc(0, range.from)),
              byteEnd: byteLength(view.state.sliceDoc(0, range.to)),
              line: line.number,
              column: range.head - line.from + 1,
            });
          }
        }
      }),
    ],
  }),
  parent: document.getElementById("editor"),
});

window.__contexture_setContent = function setContent(text) {
  suppressChangeNotification = true;
  try {
    view.dispatch({
      changes: { from: 0, to: view.state.doc.length, insert: text },
    });
  } finally {
    suppressChangeNotification = false;
  }
};

window.__contexture_getContent = function getContent() {
  return view.state.doc.toString();
};

postToNative({ type: "ready" });

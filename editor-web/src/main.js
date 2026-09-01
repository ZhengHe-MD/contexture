import { EditorView, basicSetup } from "codemirror";
import { EditorState } from "@codemirror/state";
import { markdown } from "@codemirror/lang-markdown";
import { languages } from "@codemirror/language-data";
import MarkdownIt from "markdown-it";

// Bridge protocol with the native shell (see Sources/ContextureApp/EditorBridge.swift):
//   JS -> native: window.webkit.messageHandlers.contexture.postMessage({ type, ... })
//     - { type: "ready" }
//     - { type: "contentChanged", text }
//     - { type: "previewHTML", html }
//   native -> JS: evaluateJavaScript of the window.__contexture_* functions below.
function postToNative(message) {
  if (window.webkit?.messageHandlers?.contexture) {
    window.webkit.messageHandlers.contexture.postMessage(message);
  }
}

// `html: true` preserves raw HTML the writer puts in the Document, matching
// real GFM semantics. That is exactly the untrusted-content case the Preview
// pane's isolation exists for (see editorBridgePreviewHTMLDidChange in
// Sources/ContextureApp/EditorViewController.swift and
// Sources/ContextureApp/PreviewDocumentBuilder.swift): this module only
// turns Source into an HTML string, it never renders it. The resulting
// string is untrusted and is sanitized + wrapped with a strict CSP by native
// Swift before it ever reaches the sandboxed #preview iframe below.
const markdownRenderer = new MarkdownIt({ html: true, linkify: true });

// Content pushed in from the native side (initial load, external-file reload)
// must not itself be reported back as a writer edit — but the Preview must
// still reflect it, so preview scheduling below is deliberately NOT gated by
// this flag.
let suppressChangeNotification = false;

// Re-rendering Markdown -> HTML and round-tripping it through native for
// sanitizing/wrapping on every keystroke would both thrash the Preview
// (scroll position and any highlighted text move under the mouse) and add
// pointless work while the writer is mid-word. A short debounce keeps the
// Preview "live" (issue #4's acceptance criteria) without doing that on
// every keystroke.
const PREVIEW_DEBOUNCE_MS = 150;
let previewDebounceTimer = null;

function schedulePreviewRender() {
  if (previewDebounceTimer !== null) {
    clearTimeout(previewDebounceTimer);
  }
  previewDebounceTimer = setTimeout(() => {
    previewDebounceTimer = null;
    const html = markdownRenderer.render(view.state.doc.toString());
    postToNative({ type: "previewHTML", html });
  }, PREVIEW_DEBOUNCE_MS);
}

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
        if (update.docChanged) {
          if (!suppressChangeNotification) {
            postToNative({ type: "contentChanged", text: view.state.doc.toString() });
          }
          schedulePreviewRender();
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

// The Preview iframe's document is replaced wholesale on every update (it
// cannot patch itself in place — it has no JavaScript, by design; see
// index.html). That means a naive `srcdoc` assignment resets scroll to the
// top on every keystroke, which issue #4 explicitly rules out. `contentWindow`
// stays reachable across that reload because the iframe carries
// `sandbox="allow-same-origin"` (still no `allow-scripts` — see index.html's
// comment on why that is safe), so this best-effort save/restore is enough
// to keep scroll position sensible without needing anything to execute
// inside the Preview document itself.
const previewFrame = document.getElementById("preview");

window.__contexture_setPreviewHTML = function setPreviewHTML(html) {
  let scrollY = 0;
  try {
    scrollY = previewFrame.contentWindow ? previewFrame.contentWindow.scrollY : 0;
  } catch {
    scrollY = 0;
  }
  const restoreScroll = () => {
    previewFrame.removeEventListener("load", restoreScroll);
    try {
      previewFrame.contentWindow?.scrollTo(0, scrollY);
    } catch {
      // Best-effort only: a failure here leaves the Preview scrolled to the
      // top of the new content, which is a degraded but safe outcome.
    }
  };
  previewFrame.addEventListener("load", restoreScroll);
  previewFrame.srcdoc = html;
};

postToNative({ type: "ready" });

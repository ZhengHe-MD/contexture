import { EditorView, basicSetup } from "codemirror";
import { EditorState, EditorSelection } from "@codemirror/state";
import { markdown } from "@codemirror/lang-markdown";
import { languages } from "@codemirror/language-data";
import MarkdownIt from "markdown-it";
import mermaid from "mermaid";
import {
  stampSourceRanges,
  parseBlockRange,
  smallestCoveringNodes,
  mergeNodeRanges,
  cmLinesForBlockRange,
  blockRangeForCmLines,
} from "./blockMap.js";
import {
  isLocalSVGReference,
  renderMarkdownPreview,
  sanitizeCSSReferences,
  svgDataURL,
} from "./mermaidPreview.js";
import { parseMarkdownDocument } from "./markdownDocument.js";

// Bridge protocol with the native shell (see Sources/ContextureApp/EditorBridge.swift):
//   JS -> native: window.webkit.messageHandlers.contexture.postMessage({ type, ... })
//     - { type: "ready" }
//     - { type: "contentChanged", text }
//     - { type: "selectionChanged", text, byteStart, byteEnd, line, column }
//     - { type: "documentMetadataChanged", title }
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
// Sources/ContextureApp/PreviewDocumentBuilder.swift): this module converts
// Source into an HTML string but never installs that untrusted output into a
// live document. Native Swift first sanitizes it and wraps it with a strict
// CSP before it reaches the sandboxed #preview iframe below.
//
// `stampSourceRanges` (blockMap.js) adds `data-src="<start>-<end>"` to every
// block-level element so the Source <-> Preview Selection mapping (issue #5)
// can find, for any Source line range or any point inside the rendered
// output, the corresponding block-level node in the other pane. It only
// adds attributes to markdown-it's own tokens before rendering; it does not
// change what HTML comes out, so it carries none of the untrusted-content
// risk `PreviewSanitizer`/`PreviewDocumentBuilder` guard against.
const markdownRenderer = new MarkdownIt({ html: true, linkify: true });
markdownRenderer.use(stampSourceRanges);

// Mermaid itself runs only in this trusted, bundled outer page. Diagram
// Source never runs: it is parsed with Mermaid's strict security level, the
// resulting SVG is stripped of active and remote-loading constructs, then
// encoded as an inert data: image before native Swift sanitizes and wraps the
// complete Preview. The sandboxed Preview iframe therefore keeps its existing
// no-script contract unchanged.
const MERMAID_MAX_TEXT_SIZE = 50_000;
const MERMAID_MAX_EDGES = 500;
const MERMAID_LOCKED_CONFIG = [
  "secure",
  "securityLevel",
  "startOnLoad",
  "suppressErrorRendering",
  "maxTextSize",
  "maxEdges",
];
const appearance = window.matchMedia("(prefers-color-scheme: dark)");

function initializeMermaidForAppearance(theme) {
  mermaid.initialize({
    startOnLoad: false,
    securityLevel: "strict",
    suppressErrorRendering: true,
    maxTextSize: MERMAID_MAX_TEXT_SIZE,
    maxEdges: MERMAID_MAX_EDGES,
    secure: MERMAID_LOCKED_CONFIG,
    theme,
  });
}

function sanitizedMermaidSVG(svg) {
  const parsed = new DOMParser().parseFromString(svg, "image/svg+xml");
  if (parsed.querySelector("parsererror") || parsed.documentElement.localName !== "svg") {
    throw new Error("Mermaid produced invalid SVG");
  }

  const removedElements = new Set([
    "script", "iframe", "object", "embed", "applet", "link", "meta", "base",
  ]);
  const resourceAttributes = new Set([
    "href", "src", "action", "formaction", "poster", "background", "cite",
  ]);

  for (const element of Array.from(parsed.querySelectorAll("*"))) {
    if (removedElements.has(element.localName.toLowerCase())) {
      element.remove();
      continue;
    }

    if (element.localName.toLowerCase() === "style") {
      element.textContent = sanitizeCSSReferences(element.textContent || "");
    }

    for (const attribute of Array.from(element.attributes)) {
      const name = attribute.localName.toLowerCase();
      if (name.startsWith("on")) {
        element.removeAttributeNode(attribute);
        continue;
      }
      if (resourceAttributes.has(name) && !isLocalSVGReference(attribute.value)) {
        element.removeAttributeNode(attribute);
        continue;
      }
      if (attribute.value.toLowerCase().includes("url(")) {
        element.setAttributeNS(
          attribute.namespaceURI,
          attribute.name,
          sanitizeCSSReferences(attribute.value)
        );
      }
    }
  }

  const root = parsed.documentElement;
  const directChild = (name) => Array.from(root.children)
    .find((element) => element.localName.toLowerCase() === name);
  const title = directChild("title")?.textContent?.trim() || "";
  const description = directChild("desc")?.textContent?.trim() || "";
  const accessibleName = [title, description].filter(Boolean).join(" — ") || "Mermaid diagram";

  return {
    svg: new XMLSerializer().serializeToString(root),
    accessibleName,
  };
}

async function renderMermaidDiagram(definition, previewID, diagramIndex) {
  const id = `contexture-mermaid-${previewID}-${diagramIndex}`;
  const { svg } = await mermaid.render(id, definition);
  const sanitized = sanitizedMermaidSVG(svg);
  return {
    dataURL: svgDataURL(sanitized.svg),
    accessibleName: sanitized.accessibleName,
  };
}

// Content pushed in from the native side (initial load, external-file reload)
// must not itself be reported back as a writer edit or a fresh Selection —
// but the Preview must still reflect it, so preview scheduling below is
// deliberately NOT gated by this flag.
let suppressChangeNotification = false;

const byteLength = (text) => new TextEncoder().encode(text).length;

// Re-rendering Markdown -> HTML and round-tripping it through native for
// sanitizing/wrapping on every keystroke would both thrash the Preview
// (scroll position and any highlighted text move under the mouse) and add
// pointless work while the writer is mid-word. A short debounce keeps the
// Preview "live" (issue #4's acceptance criteria) without doing that on
// every keystroke. The Source -> Preview highlight (issue #5) piggybacks on
// this same debounce rather than getting its own: it can only be reapplied
// once new `data-src` elements exist in the reloaded iframe document anyway
// (see the `load` listener in __contexture_setPreviewHTML below), so there
// is nothing to gain from recomputing it any more often than the Preview
// itself re-renders, and doing so keeps this responsive while typing in a
// large Document (issue #5's explicit acceptance criterion) for the same
// reason the render debounce already does.
const PREVIEW_DEBOUNCE_MS = 150;
let previewDebounceTimer = null;
let previewRenderID = 0;

function schedulePreviewRender() {
  const scheduledID = ++previewRenderID;
  const document = parseMarkdownDocument(view.state.doc.toString());
  postToNative({ type: "documentMetadataChanged", title: document.title });
  if (previewDebounceTimer !== null) {
    clearTimeout(previewDebounceTimer);
  }
  previewDebounceTimer = setTimeout(async () => {
    previewDebounceTimer = null;
    const theme = appearance.matches ? "dark" : "default";
    initializeMermaidForAppearance(theme);
    const html = await renderMarkdownPreview(
      markdownRenderer,
      document.previewSource,
      (definition, diagramIndex) => renderMermaidDiagram(definition, scheduledID, diagramIndex)
    );
    // A slower, older Mermaid render must never overwrite newer Source or a
    // newly-selected appearance after its replacement is already underway.
    if (scheduledID === previewRenderID) {
      postToNative({ type: "previewHTML", html });
    }
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
        // Order matters: native's cached full-document text (used to
        // compute a Selection Snapshot's revision hash) must be current
        // before it processes a selectionChanged message for the same
        // update, so contentChanged is always posted before selectionChanged
        // below. The Preview, unlike contentChanged/selectionChanged, must
        // reflect native-pushed content too (initial load, external
        // reload), so scheduling it is not gated by suppressChangeNotification.
        if (update.docChanged) {
          if (!suppressChangeNotification) {
            postToNative({ type: "contentChanged", text: view.state.doc.toString() });
          }
          schedulePreviewRender();
        }

        // Selecting is sharing — there is no separate share gesture — but
        // only a non-empty range is a Selection. A collapse to an empty
        // range is deliberately NOT reported: Arming survives the visible
        // Selection collapsing (docs/product.md "Arming"), so silence here,
        // not a clear, is what keeps a previously Armed Snapshot alive.
        //
        // This fires for a Source-originated selection AND for a
        // Preview-originated one once handlePreviewSelectionChanged below
        // dispatches the snapped range into this same view — that reuse is
        // deliberate (see blockMap.js and handlePreviewSelectionChanged's
        // doc comment): there is exactly one path from "a Selection changed
        // somewhere" to "native has been told", not two.
        if (update.selectionSet && !suppressChangeNotification) {
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
            applyPreviewHighlightForSelection(range);
          } else {
            // Nothing is visibly selected in the Source right now. This is
            // purely cosmetic (it clears the Preview highlight class) and
            // is independent of Bridge Arming, which deliberately survives
            // a collapse (see the comment above) — the two are different
            // concerns: "what is currently visibly selected" vs. "what is
            // currently Armed for sharing".
            clearPreviewHighlight();
          }
        }
      }),
    ],
  }),
  parent: document.getElementById("editor"),
});

appearance.addEventListener("change", schedulePreviewRender);

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
    // The reload just replaced every element in the iframe document,
    // including whatever this module previously added the highlight class
    // to — reapply it (against the freshly stamped `data-src` elements) for
    // whatever is still the current Source selection, if any.
    const range = view.state.selection.main;
    if (!range.empty) {
      applyPreviewHighlightForSelection(range);
    }
  };
  previewFrame.addEventListener("load", restoreScroll);
  previewFrame.srcdoc = html;
};

// --- Synchronized Selection (issue #5) ---
//
// A Selection made in either pane is shown in both. What is published to
// native (and from there, the Selection Bridge) is always a Source range —
// see docs/architecture/selection-bridge.md "Selection acquisition" — so a
// Preview-originated selection is never reported through a second path; it
// is turned into a CodeMirror selection (below) and then flows through the
// exact same `update.selectionSet` handling above that a Source-originated
// selection already used.

const PREVIEW_HIGHLIGHT_CLASS = "contexture-selected";
let highlightedPreviewElements = [];

/// Returns every direct child element of `element` that carries `data-src`
/// — i.e. the block-level children stampSourceRanges (blockMap.js) put
/// there. This is the one place the DOM is walked; everything about
/// *which* of these matter for a given range lives in the pure, tested
/// `smallestCoveringNodes` (blockMap.js).
function dataSrcChildren(element) {
  return Array.from(element.children).filter((child) => child.hasAttribute("data-src"));
}

/// Wraps a Preview DOM element as a `smallestCoveringNodes`-shaped node.
/// `children` is a getter so a large Preview document is walked lazily —
/// only the branch actually visited during a search is ever converted, not
/// the whole tree up front — which is what keeps this cheap enough to run
/// on every Selection change in a large Document (issue #5's explicit
/// responsiveness criterion).
function toBlockNode(element) {
  const range = parseBlockRange(element.getAttribute("data-src"));
  return {
    start: range.start,
    end: range.end,
    get children() {
      return dataSrcChildren(element).map(toBlockNode);
    },
    element,
  };
}

/// The synthetic root `smallestCoveringNodes` searches from: an
/// unbounded range whose children are the Preview document's top-level
/// stamped blocks.
function previewTreeRoot(previewDocument) {
  return {
    start: -Infinity,
    end: Infinity,
    children: dataSrcChildren(previewDocument.body).map(toBlockNode),
  };
}

function clearPreviewHighlight() {
  for (const element of highlightedPreviewElements) {
    element.classList.remove(PREVIEW_HIGHLIGHT_CLASS);
  }
  highlightedPreviewElements = [];
}

/// Source -> Preview highlight. `range` is a CodeMirror selection range
/// (character offsets in the Source). Finds the smallest set of complete
/// Preview nodes covering the Source lines that range touches, and marks
/// them with `PREVIEW_HIGHLIGHT_CLASS` (styled by
/// PreviewDocumentBuilder's embedded CSS — see its doc comment). This is
/// DOM manipulation of the sandboxed iframe's document from the *outer*,
/// trusted script, exactly like the existing scroll save/restore above —
/// nothing executes inside the Preview document itself (verified
/// empirically: see the top-level report for how classList mutation and
/// its effect on computed style were confirmed to work against a
/// sandbox="allow-same-origin" (no allow-scripts) srcdoc iframe, the same
/// access path this function relies on).
function applyPreviewHighlightForSelection(range) {
  const previewDocument = previewFrame.contentDocument;
  if (!previewDocument || !previewDocument.body) return;
  clearPreviewHighlight();

  const fromLine = view.state.doc.lineAt(range.from).number;
  const toLine = view.state.doc.lineAt(range.to).number;
  const target = blockRangeForCmLines(fromLine, toLine);

  const covering = smallestCoveringNodes(previewTreeRoot(previewDocument), target);
  for (const node of covering) {
    // The synthetic root itself has no `element` and is only ever returned
    // when the target range fell outside every stamped block (e.g. it
    // pointed at a trailing blank line with nothing rendered for it) — a
    // safe no-op, not a partial/incorrect highlight.
    if (node.element) {
      node.element.classList.add(PREVIEW_HIGHLIGHT_CLASS);
      highlightedPreviewElements.push(node.element);
    }
  }
}

/// Walks up from a DOM node inside the Preview document to the nearest
/// ancestor element carrying `data-src`, or null if none exists (e.g. the
/// node is inside a raw HTML block, which stampSourceRanges does not stamp
/// — see blockMap.js's doc comment on that documented gap).
function nearestDataSrcElement(node, previewDocument) {
  let element = node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement;
  while (element && element !== previewDocument.body && !element.hasAttribute("data-src")) {
    element = element.parentElement;
  }
  return element && element.hasAttribute("data-src") ? element : null;
}

/// Preview -> Source selection. Called when polling (below) detects the
/// writer's live selection inside the Preview iframe changed. Resolves the
/// block-level Source line range the writer's raw (possibly
/// mid-styled-span, mid-link) selection touches, snaps it outward via the
/// same `smallestCoveringNodes` search Source -> Preview highlighting uses,
/// and dispatches *that* as the real CodeMirror selection.
///
/// This is the whole point of routing through CodeMirror rather than
/// publishing a second, Preview-specific payload: once dispatched, the
/// `updateListener` above already knows how to turn a non-empty CM
/// selection into byteStart/byteEnd/line/column, post it to native, and
/// re-highlight the Preview — all of that fires unchanged, so nothing here
/// duplicates it.
function handlePreviewSelectionChanged(selection) {
  const previewDocument = previewFrame.contentDocument;
  if (!previewDocument) return;
  const domRange = selection.getRangeAt(0);
  const startElement = nearestDataSrcElement(domRange.startContainer, previewDocument);
  const endElement = nearestDataSrcElement(domRange.endContainer, previewDocument);
  if (!startElement || !endElement) return;

  const startRange = parseBlockRange(startElement.getAttribute("data-src"));
  const endRange = parseBlockRange(endElement.getAttribute("data-src"));
  if (!startRange || !endRange) return;

  const touched = {
    start: Math.min(startRange.start, endRange.start),
    end: Math.max(startRange.end, endRange.end),
  };
  const covering = smallestCoveringNodes(previewTreeRoot(previewDocument), touched);
  if (covering.length === 0) return;
  const snapped = mergeNodeRanges(covering);
  // Defense in depth, not expected to trigger: `touched` is always derived
  // from at least one real stamped block above, so `covering` should never
  // bottom out at the synthetic, unbounded root node (see blockMap.js's
  // `smallestCoveringNodes` contract). If it somehow did, `snapped` would
  // be unbounded — refusing to proceed here, rather than clamping it to
  // "the whole Document", is what keeps that failure mode a no-op instead
  // of silently violating "never expand a Selection to the whole Document"
  // (docs/product.md "Privacy and safety").
  if (!Number.isFinite(snapped.start) || !Number.isFinite(snapped.end)) return;
  const { fromLine, toLine } = cmLinesForBlockRange(snapped);

  const lineCount = view.state.doc.lines;
  const clampedFromLine = Math.min(Math.max(fromLine, 1), lineCount);
  const clampedToLine = Math.min(Math.max(toLine, 1), lineCount);
  const from = view.state.doc.line(clampedFromLine).from;
  const to = view.state.doc.line(clampedToLine).to;
  if (from >= to) return;

  view.dispatch({ selection: EditorSelection.range(from, to), scrollIntoView: true });

  // Clear the writer's raw, un-snapped native Preview selection so the
  // pane shows only the canonical (snapped) highlight — reapplied a moment
  // later by the dispatch above's own selectionSet handling — rather than
  // both the rough drag and the snapped range at once.
  try {
    selection.removeAllRanges();
  } catch {
    // Best-effort cosmetic cleanup; leaving the raw selection visible
    // alongside the highlight is a degraded but harmless outcome.
  }
  lastPreviewSelectionPoint = null;
}

// Detecting a Preview selection is NOT event-driven. This was verified
// empirically before committing to it, not assumed: a standalone WKWebView
// harness reproducing this exact sandbox="allow-same-origin" (no
// allow-scripts) srcdoc iframe setup showed that `contentDocument` and
// `contentWindow` ARE reachable from the outer trusted page (confirming
// what the scroll save/restore code above already relied on), and that
// `contentWindow.getSelection()` DOES correctly reflect the sandboxed
// document's live Selection state — but that no event, including
// `selectionchange` added directly on `contentDocument` and even a
// same-named event dispatched manually via `dispatchEvent`, is ever
// delivered to a listener on that document. WebKit does not run a
// script-disabled document's own event/task-queue machinery, even for
// events originating from a privileged same-origin embedder. Polling
// `contentWindow.getSelection()` from the outer page's own timer sidesteps
// that entirely — it is a plain property read, not something that depends
// on the sandboxed document dispatching anything — and was confirmed
// working the same way. See the top-level report for the harness details.
const PREVIEW_SELECTION_POLL_MS = 200;
let lastPreviewSelectionPoint = null;

function previewSelectionPollTick() {
  let selection;
  try {
    selection = previewFrame.contentWindow ? previewFrame.contentWindow.getSelection() : null;
  } catch {
    return;
  }
  if (!selection || selection.isCollapsed || selection.rangeCount === 0) {
    lastPreviewSelectionPoint = null;
    return;
  }
  const domRange = selection.getRangeAt(0);
  const current = {
    startContainer: domRange.startContainer,
    startOffset: domRange.startOffset,
    endContainer: domRange.endContainer,
    endOffset: domRange.endOffset,
  };
  if (
    lastPreviewSelectionPoint &&
    lastPreviewSelectionPoint.startContainer === current.startContainer &&
    lastPreviewSelectionPoint.startOffset === current.startOffset &&
    lastPreviewSelectionPoint.endContainer === current.endContainer &&
    lastPreviewSelectionPoint.endOffset === current.endOffset
  ) {
    return; // Unchanged since the last tick — nothing to do.
  }
  lastPreviewSelectionPoint = current;
  handlePreviewSelectionChanged(selection);
}

// A fixed, lightweight timer rather than anything tied to Document size or
// keystroke rate: each tick is a handful of property reads plus (only on an
// actual change) a bounded DOM ancestor walk and a `view.dispatch` — none
// of it scales with Document length, so this stays cheap regardless of how
// large the Document is (issue #5's "stays responsive while typing in a
// large Document" criterion).
setInterval(previewSelectionPollTick, PREVIEW_SELECTION_POLL_MS);

postToNative({ type: "ready" });

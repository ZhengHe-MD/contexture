// Pure orchestration for replacing Markdown `mermaid` fences with inert
// diagram images. The browser-specific Mermaid API and SVG sanitization live
// in main.js; keeping token transformation here makes the contract testable in
// Node without pretending that a DOM shim is WebKit.

function escapeHTML(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

export function isLocalSVGReference(value) {
  return String(value).trim().startsWith("#");
}

export function sanitizeCSSReferences(css) {
  return css
    .replace(/@import[\s\S]*?(?:;|$)/gi, "")
    .replace(/url\(([^)]*)\)/gi, (match, rawTarget) => {
      const target = rawTarget.trim().replace(/^(['"])(.*)\1$/, "$2").trim();
      return isLocalSVGReference(target) ? match : "none";
    });
}

export function svgDataURL(svg) {
  const bytes = new TextEncoder().encode(svg);
  const chunks = [];
  const chunkSize = 0x8000;
  for (let start = 0; start < bytes.length; start += chunkSize) {
    chunks.push(String.fromCharCode(...bytes.subarray(start, start + chunkSize)));
  }
  return `data:image/svg+xml;base64,${btoa(chunks.join(""))}`;
}

export function isMermaidFence(token) {
  if (token.type !== "fence") return false;
  const [language] = token.info.trim().split(/\s+/, 1);
  return language === "mermaid";
}

export function summarizeMermaidError(error) {
  const raw = error instanceof Error ? error.message : String(error || "Unknown error");
  const compact = raw.replace(/\s+/g, " ").trim();
  return compact.length > 400 ? `${compact.slice(0, 397)}...` : compact;
}

function replaceWithHTML(token, html) {
  token.type = "html_block";
  token.tag = "";
  token.nesting = 0;
  token.attrs = null;
  token.map = null;
  token.children = null;
  token.content = `${html}\n`;
}

function renderedDiagramHTML(dataSrc, diagram) {
  return [
    `<figure class="contexture-mermaid" data-src="${escapeHTML(dataSrc)}">`,
    `<img src="${escapeHTML(diagram.dataURL)}" alt="${escapeHTML(diagram.accessibleName || "Mermaid diagram")}">`,
    "</figure>",
  ].join("");
}

function diagramErrorHTML(dataSrc, error) {
  const message = summarizeMermaidError(error);
  return `<pre class="contexture-mermaid-error" data-src="${escapeHTML(dataSrc)}"><code>Mermaid diagram error: ${escapeHTML(message)}</code></pre>`;
}

/// Parses Markdown once, renders all Mermaid Blocks concurrently, and emits
/// one complete HTML result. Each diagram failure is isolated at its own
/// Source range so another block cannot prevent the rest of the Preview.
export async function renderMarkdownPreview(markdownRenderer, source, renderDiagram) {
  const environment = {};
  const tokens = markdownRenderer.parse(source, environment);
  const jobs = [];
  let diagramIndex = 0;

  for (const token of tokens) {
    if (!isMermaidFence(token)) continue;

    const currentIndex = diagramIndex++;
    const dataSrc = token.attrGet("data-src") || `${token.map[0]}-${token.map[1]}`;
    jobs.push(
      Promise.resolve()
        .then(() => renderDiagram(token.content, currentIndex))
        .then(
          (diagram) => replaceWithHTML(token, renderedDiagramHTML(dataSrc, diagram)),
          (error) => replaceWithHTML(token, diagramErrorHTML(dataSrc, error))
        )
    );
  }

  await Promise.all(jobs);
  return markdownRenderer.renderer.render(tokens, markdownRenderer.options, environment);
}

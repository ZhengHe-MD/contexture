import assert from "node:assert/strict";
import test from "node:test";
import MarkdownIt from "markdown-it";
import { stampSourceRanges } from "./blockMap.js";
import {
  isLocalSVGReference,
  isMermaidFence,
  renderMarkdownPreview,
  sanitizeCSSReferences,
  summarizeMermaidError,
  svgDataURL,
} from "./mermaidPreview.js";

function renderer() {
  const markdown = new MarkdownIt({ html: true, linkify: true });
  markdown.use(stampSourceRanges);
  return markdown;
}

test("recognizes only a lowercase mermaid first info-string token", () => {
  assert.equal(isMermaidFence({ type: "fence", info: "mermaid" }), true);
  assert.equal(isMermaidFence({ type: "fence", info: "mermaid title=Example" }), true);
  assert.equal(isMermaidFence({ type: "fence", info: "Mermaid" }), false);
  assert.equal(isMermaidFence({ type: "fence", info: " mermaidish " }), false);
  assert.equal(isMermaidFence({ type: "code_block", info: "mermaid" }), false);
});

test("allows only fragment-local SVG resource references", () => {
  assert.equal(isLocalSVGReference("#arrowhead"), true);
  assert.equal(isLocalSVGReference("  #filter  "), true);
  assert.equal(isLocalSVGReference("https://example.com/image.svg"), false);
  assert.equal(isLocalSVGReference("data:image/svg+xml;base64,AAAA"), false);
  assert.equal(isLocalSVGReference("javascript:alert(1)"), false);
});

test("removes CSS imports and non-fragment URL loads while preserving SVG markers", () => {
  const css = [
    '@import url("https://example.com/theme.css");',
    ".edge { marker-end: url(#arrowhead); }",
    ".node { background: url(https://example.com/beacon); }",
  ].join("\n");
  const sanitized = sanitizeCSSReferences(css);
  assert.doesNotMatch(sanitized, /@import|https:\/\//);
  assert.match(sanitized, /marker-end: url\(#arrowhead\)/);
  assert.match(sanitized, /background: none/);
});

test("encodes Unicode SVG as a base64 data image", () => {
  const dataURL = svgDataURL("<svg><text>你好</text></svg>");
  assert.match(dataURL, /^data:image\/svg\+xml;base64,/);
  const decoded = Buffer.from(dataURL.split(",", 2)[1], "base64").toString("utf8");
  assert.equal(decoded, "<svg><text>你好</text></svg>");
});

test("replaces a Mermaid Block with an inert image at the full fenced Source range", async () => {
  const html = await renderMarkdownPreview(
    renderer(),
    "Before\n\n```mermaid\nflowchart LR\nA-->B\n```\n\nAfter\n",
    async (definition, index) => {
      assert.equal(definition, "flowchart LR\nA-->B\n");
      assert.equal(index, 0);
      return {
        dataURL: "data:image/svg+xml;base64,PHN2Zz48L3N2Zz4=",
        accessibleName: "A to B",
      };
    }
  );

  assert.match(html, /<figure class="contexture-mermaid" data-src="2-6">/);
  assert.match(html, /<img src="data:image\/svg\+xml;base64,PHN2Zz48L3N2Zz4=" alt="A to B">/);
  assert.doesNotMatch(html, /language-mermaid/);
  assert.match(html, /<p data-src="0-1">Before<\/p>/);
  assert.match(html, /<p data-src="7-8">After<\/p>/);
});

test("leaves differently-cased and non-Mermaid fences as ordinary code", async () => {
  let renderCount = 0;
  const html = await renderMarkdownPreview(
    renderer(),
    "```Mermaid\nA-->B\n```\n\n```js\nconst x = 1;\n```\n",
    async () => {
      renderCount += 1;
      throw new Error("must not be called");
    }
  );

  assert.equal(renderCount, 0);
  assert.match(html, /class="language-Mermaid"/);
  assert.match(html, /class="language-js"/);
});

test("starts every diagram render before waiting and preserves document order", async () => {
  const resolvers = [];
  const started = [];
  const preview = renderMarkdownPreview(
    renderer(),
    "```mermaid\nfirst\n```\n\n```mermaid\nsecond\n```\n",
    (definition, index) => {
      started.push({ definition, index });
      return new Promise((resolve) => resolvers.push(resolve));
    }
  );

  await Promise.resolve();
  assert.deepEqual(started, [
    { definition: "first\n", index: 0 },
    { definition: "second\n", index: 1 },
  ]);
  resolvers[1]({ dataURL: "data:image/svg+xml;base64,c2Vjb25k", accessibleName: "Second" });
  resolvers[0]({ dataURL: "data:image/svg+xml;base64,Zmlyc3Q=", accessibleName: "First" });

  const html = await preview;
  assert.ok(html.indexOf("alt=\"First\"") < html.indexOf("alt=\"Second\""));
});

test("isolates a bad diagram as an escaped inline error", async () => {
  const html = await renderMarkdownPreview(
    renderer(),
    "```mermaid\nbad\n```\n\n```mermaid\ngood\n```\n",
    async (definition) => {
      if (definition === "bad\n") throw new Error("Parse <error> & details");
      return { dataURL: "data:image/svg+xml;base64,Z29vZA==", accessibleName: "Good" };
    }
  );

  assert.match(html, /class="contexture-mermaid-error" data-src="0-3"/);
  assert.match(html, /Parse &lt;error&gt; &amp; details/);
  assert.match(html, /class="contexture-mermaid" data-src="4-7"/);
});

test("escapes image attributes and supplies the accessible-name fallback", async () => {
  const html = await renderMarkdownPreview(renderer(), "```mermaid\nA\n```\n", async () => ({
    dataURL: 'data:image/svg+xml;base64,x\" onerror=\"bad',
    accessibleName: "",
  }));

  assert.match(html, /src="data:image\/svg\+xml;base64,x&quot; onerror=&quot;bad"/);
  assert.match(html, /alt="Mermaid diagram"/);
});

test("compacts and bounds Mermaid errors", () => {
  const message = summarizeMermaidError(new Error(`bad\n\n${"x".repeat(500)}`));
  assert.equal(message.includes("\n"), false);
  assert.equal(message.length, 400);
  assert.equal(message.endsWith("..."), true);
});

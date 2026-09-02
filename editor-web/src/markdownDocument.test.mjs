import assert from "node:assert/strict";
import test from "node:test";
import MarkdownIt from "markdown-it";
import { stampSourceRanges } from "./blockMap.js";
import { parseMarkdownDocument } from "./markdownDocument.js";
import { renderMarkdownPreview } from "./mermaidPreview.js";

function renderer() {
  const markdown = new MarkdownIt({ html: true, linkify: true });
  markdown.use(stampSourceRanges);
  return markdown;
}

test("front matter supplies the title but is absent from Preview", async () => {
  const source = [
    "---",
    "title: A Writer's Page",
    "status: draft",
    "---",
    "# Introduction",
    "",
  ].join("\n");

  const document = parseMarkdownDocument(source);
  const html = await renderMarkdownPreview(renderer(), document.previewSource, async () => {
    throw new Error("no Mermaid Blocks expected");
  });

  assert.equal(document.title, "A Writer's Page");
  assert.doesNotMatch(html, /title:|status:|<hr/);
  assert.match(html, /<h1 data-src="4-5">Introduction<\/h1>/);
});

test("quoted title scalars are decoded", () => {
  assert.equal(
    parseMarkdownDocument('---\ntitle: "A: \\"quoted\\" title"\n---\nBody\n').title,
    'A: "quoted" title'
  );
  assert.equal(
    parseMarkdownDocument("---\ntitle: 'Writer''s title'\n---\nBody\n").title,
    "Writer's title"
  );
});

test("a folded YAML title becomes one native window title", () => {
  assert.equal(
    parseMarkdownDocument("---\ntitle: >-\n  A longer page\n  title\n---\nBody\n").title,
    "A longer page title"
  );
  assert.equal(
    parseMarkdownDocument("---\ntitle: |-\n  A longer page\n  title\n---\nBody\n").title,
    "A longer page title"
  );
});

test("the YAML document-end marker may close front matter", async () => {
  const document = parseMarkdownDocument("---\ntitle: Page\n...\n# Body\n");
  const html = await renderMarkdownPreview(renderer(), document.previewSource, async () => {
    throw new Error("no Mermaid Blocks expected");
  });

  assert.equal(document.title, "Page");
  assert.doesNotMatch(html, /title:|<hr/);
  assert.match(html, /<h1 data-src="3-4">Body<\/h1>/);
});

test("a missing or empty title uses the native document-name fallback", () => {
  assert.equal(parseMarkdownDocument("---\nstatus: draft\n---\nBody\n").title, null);
  assert.equal(parseMarkdownDocument("---\ntitle:   \n---\nBody\n").title, null);
});

test("an unclosed or non-leading delimiter remains ordinary Markdown", () => {
  for (const source of ["---\ntitle: Still Source\n", "Intro\n\n---\ntitle: Still Source\n---\n"]) {
    assert.deepEqual(parseMarkdownDocument(source), { title: null, previewSource: source });
  }
});

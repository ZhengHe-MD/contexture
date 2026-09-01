// Headless coverage for the pure block-mapping logic in blockMap.js (issue
// #5). Run with `npm test` (== `node --test src`) from editor-web/. This is
// Node's own built-in test runner -- no new dependency -- exercising the
// exact functions main.js wires into the DOM, not a reimplementation of
// them. See blockMap.js's top-of-file comment for why the mapping stops at
// block granularity rather than reaching for inline (bold/link) nodes.
//
// What this file does NOT cover, and why: applying the highlight CSS class
// to real Preview DOM elements, walking a live `previewFrame.contentDocument`,
// and the `setInterval` polling loop in main.js all require an actual DOM
// and a live WKWebView (this project has no jsdom dependency and does not
// add one here). Those stay thin, deliberately un-clever wrappers around
// the functions tested below; see the top-level report for how their
// real-WKWebView behavior was instead verified empirically.
import { test } from "node:test";
import assert from "node:assert/strict";
import MarkdownIt from "markdown-it";
import {
  stampSourceRanges,
  formatBlockRange,
  parseBlockRange,
  smallestCoveringNodes,
  mergeNodeRanges,
  cmLinesForBlockRange,
  blockRangeForCmLines,
} from "./blockMap.js";

test("formatBlockRange / parseBlockRange round-trip", () => {
  assert.equal(formatBlockRange({ start: 4, end: 8 }), "4-8");
  assert.deepEqual(parseBlockRange("4-8"), { start: 4, end: 8 });
});

test("parseBlockRange returns null for missing or malformed input", () => {
  assert.equal(parseBlockRange(null), null);
  assert.equal(parseBlockRange(""), null);
  assert.equal(parseBlockRange("not-a-range"), null);
  assert.equal(parseBlockRange("4"), null);
  assert.equal(parseBlockRange("-4-8"), null);
});

test("cmLinesForBlockRange / blockRangeForCmLines round-trip and off-by-one boundaries", () => {
  // A single-line paragraph: markdown-it map [2,3) (0-based, end-exclusive)
  // is CM's line 3 alone (1-based, inclusive).
  assert.deepEqual(cmLinesForBlockRange({ start: 2, end: 3 }), { fromLine: 3, toLine: 3 });
  assert.deepEqual(blockRangeForCmLines(3, 3), { start: 2, end: 3 });

  // A multi-line block: markdown-it map [8,10) is CM lines 9-10 inclusive.
  assert.deepEqual(cmLinesForBlockRange({ start: 8, end: 10 }), { fromLine: 9, toLine: 10 });
  assert.deepEqual(blockRangeForCmLines(9, 10), { start: 8, end: 10 });
});

test("smallestCoveringNodes recurses into a single fully-containing child", () => {
  const tree = {
    start: -Infinity,
    end: Infinity,
    children: [
      { start: 0, end: 2, children: [] },
      {
        start: 2,
        end: 6,
        children: [
          { start: 2, end: 4, children: [] },
          { start: 4, end: 6, children: [] },
        ],
      },
    ],
  };
  // Range [2,4) sits fully inside the [2,6) node, and fully inside its
  // [2,4) child -- the search should go as small as the tree allows.
  const result = smallestCoveringNodes(tree, { start: 2, end: 4 });
  assert.deepEqual(result, [{ start: 2, end: 4, children: [] }]);
});

test("smallestCoveringNodes returns sibling set when the range spans two children (snap outward)", () => {
  const listItem1 = { start: 4, end: 5, children: [] };
  const listItem2 = { start: 5, end: 8, children: [] };
  const list = { start: 4, end: 8, children: [listItem1, listItem2] };
  const tree = { start: -Infinity, end: Infinity, children: [list] };

  // A selection touching part of item 1 and part of item 2 must snap
  // outward to both list items, not up to the whole <ul>.
  const result = smallestCoveringNodes(tree, { start: 4, end: 6 });
  assert.deepEqual(result, [listItem1, listItem2]);
});

test("smallestCoveringNodes bottoms out at a leaf with no covering children", () => {
  const paragraph = { start: 2, end: 3, children: [] };
  const tree = { start: -Infinity, end: Infinity, children: [paragraph] };
  const result = smallestCoveringNodes(tree, { start: 2, end: 3 });
  assert.deepEqual(result, [paragraph]);
});

test("smallestCoveringNodes handles multi-level nesting (nested list inside a list item)", () => {
  const nestedItem = { start: 6, end: 8, children: [] };
  const nestedList = { start: 6, end: 8, children: [nestedItem] };
  const outerItem2 = { start: 5, end: 8, children: [nestedList] };
  const outerItem1 = { start: 4, end: 5, children: [] };
  const outerList = { start: 4, end: 8, children: [outerItem1, outerItem2] };
  const tree = { start: -Infinity, end: Infinity, children: [outerList] };

  // A selection fully inside the nested item should recurse all the way
  // down to it, through outerList -> outerItem2 -> nestedList -> nestedItem.
  const result = smallestCoveringNodes(tree, { start: 6, end: 8 });
  assert.deepEqual(result, [nestedItem]);
});

test("mergeNodeRanges unions a covering set's ranges", () => {
  const nodes = [
    { start: 4, end: 5 },
    { start: 5, end: 8 },
  ];
  assert.deepEqual(mergeNodeRanges(nodes), { start: 4, end: 8 });
});

// --- Integration tests against the real markdown-it dependency ---
// These lock in the empirically-verified stamping behavior (see the
// top-level report) as an automated regression guard, rather than relying
// on a one-off manual check.

function render(src) {
  const md = new MarkdownIt({ html: true, linkify: true });
  md.use(stampSourceRanges);
  return md.render(src);
}

test("stamps a heading and paragraph with their own line ranges", () => {
  const html = render("# Heading\n\nA paragraph.\n");
  assert.match(html, /<h1 data-src="0-1">Heading<\/h1>/);
  assert.match(html, /<p data-src="2-3">A paragraph\.<\/p>/);
});

test("stamps nested list items with progressively tighter ranges, not just the top-level list", () => {
  const html = render("- item one\n- item two\n  - nested item\n");
  assert.match(html, /<ul data-src="0-3">/);
  assert.match(html, /<li data-src="0-1">item one<\/li>/);
  // item two's own <li> range covers both its own line and the nested list.
  assert.match(html, /<li data-src="1-3">item two/);
  assert.match(html, /<ul data-src="2-3">/);
  assert.match(html, /<li data-src="2-3">nested item<\/li>/);
});

test("loose list items get their own inner paragraph range, tighter than the <li>", () => {
  const html = render("- loose one\n\n- loose two\n");
  assert.match(html, /<li data-src="0-2">\s*<p data-src="0-1">loose one<\/p>\s*<\/li>/);
  assert.match(html, /<li data-src="2-3">\s*<p data-src="2-3">loose two<\/p>\s*<\/li>/);
});

test("stamps a table's rows but not individual cells", () => {
  const html = render("| a | b |\n| - | - |\n| 1 | 2 |\n");
  assert.match(html, /<tr data-src="0-1">/); // header row
  assert.match(html, /<tr data-src="2-3">/); // body row
  assert.ok(!html.includes("<th data-src"));
  assert.ok(!html.includes("<td data-src"));
});

test("stamps a fenced code block and a blockquote", () => {
  const html = render("```js\nconst x = 1;\n```\n\n> quoted\n> text\n");
  assert.match(html, /<code data-src="0-3"/);
  assert.match(html, /<blockquote data-src="4-6">/);
});

test("does not stamp a raw HTML block (documented gap)", () => {
  const html = render("<div>raw html</div>\n");
  assert.ok(!html.includes("data-src"));
});

// --- The core invariant: whatever gets published is always parseable ---
// Real test cases per the ticket brief: a selection starting mid-**bold**,
// mid-link, spanning part of a table cell, and inside a fenced code block.
// Under this module's block-level granularity all four resolve to their
// single containing block (paragraph / table row / fenced code block —
// see the top-of-file comment on why inline nodes are out of scope), so
// this test slices the real Source by that block's line range (the same
// arithmetic main.js uses, via cmLinesForBlockRange, before calling
// `view.state.doc.line(n)`) and confirms the result is always a complete,
// independently-parseable construct — never a truncated one.

function sliceSourceByCmLines(source, fromLine, toLine) {
  return source.split("\n").slice(fromLine - 1, toLine).join("\n");
}

test("invariant: snapping to the containing block yields complete, parseable Markdown for tricky mid-node selections", () => {
  const source =
    'A paragraph with **bold text** and a [link](https://example.com/x "t") inside it.\n' +
    "\n" +
    "| a | b |\n" +
    "| - | - |\n" +
    "| 1 | 2 |\n" +
    "\n" +
    "```js\n" +
    "const x = 1;\n" +
    "```\n";
  const html = render(source);

  // A selection starting mid-**bold** or mid-link: both are inline nodes
  // inside the same paragraph, so both resolve to that paragraph's own
  // data-src.
  assert.match(html, /^<p data-src="0-1">/);
  const paragraphCmLines = cmLinesForBlockRange({ start: 0, end: 1 });
  const paragraphSlice = sliceSourceByCmLines(source, paragraphCmLines.fromLine, paragraphCmLines.toLine);
  assert.equal(paragraphSlice, 'A paragraph with **bold text** and a [link](https://example.com/x "t") inside it.');
  const reparsedParagraph = render(paragraphSlice);
  // The bold span and the link (its target included) survive intact, not
  // truncated at either boundary.
  assert.match(reparsedParagraph, /<strong>bold text<\/strong>/);
  assert.match(reparsedParagraph, /<a href="https:\/\/example\.com\/x" title="t">link<\/a>/);

  // A selection spanning part of a table cell resolves to the containing
  // row, not just that cell.
  const bodyRowMatch = /<tr data-src="(\d+-\d+)">\s*<td>1<\/td>/.exec(html);
  assert.ok(bodyRowMatch, "expected to find the body row's data-src");
  const rowCmLines = cmLinesForBlockRange(parseBlockRange(bodyRowMatch[1]));
  const rowSlice = sliceSourceByCmLines(source, rowCmLines.fromLine, rowCmLines.toLine);
  assert.equal(rowSlice, "| 1 | 2 |");
  // "Parseable" does not mean "keeps the same semantic role it had in
  // context": a lone body row without its header + delimiter row is not,
  // on its own, GFM table syntax (a table needs the header to establish
  // table-ness) -- markdown-it correctly renders it as an ordinary
  // paragraph of literal pipe-delimited text instead of a <table>. That is
  // still well-formed, independently parseable Markdown (the actual
  // invariant), not an error -- it just is not a table anymore, which is
  // inherent to GFM's table grammar, not a flaw in this snap.
  assert.equal(render(rowSlice), '<p data-src="0-1">| 1 | 2 |</p>\n');

  // A selection inside a fenced code block resolves to the whole fence,
  // both delimiters included -- never a slice that opens a fence without
  // closing it (which would swallow whatever followed if concatenated
  // elsewhere).
  const fenceMatch = /<code data-src="(\d+-\d+)"/.exec(html);
  assert.ok(fenceMatch, "expected to find the fence's data-src");
  const fenceCmLines = cmLinesForBlockRange(parseBlockRange(fenceMatch[1]));
  const fenceSlice = sliceSourceByCmLines(source, fenceCmLines.fromLine, fenceCmLines.toLine);
  assert.equal(fenceSlice, "```js\nconst x = 1;\n```");
  assert.match(render(fenceSlice), /<pre><code data-src="0-3" class="language-js">const x = 1;\n<\/code><\/pre>/);
});

test("does not stamp inline spans (bold, link) -- only their containing block", () => {
  const html = render('A paragraph with **bold** and a [link](https://example.com/x "t").\n');
  assert.match(html, /^<p data-src="0-1">/);
  assert.ok(!html.includes("<strong data-src"));
  assert.ok(!html.includes("<a data-src"));
  // The link's target is part of the paragraph's own Source, so it is
  // trivially included whenever this block is what gets selected/published.
  assert.match(html, /<a href="https:\/\/example\.com\/x"/);
});

import { test } from "node:test";
import assert from "node:assert/strict";
import {
  parseHTMLBlocks,
  stampHTMLPreview,
  snapHTMLBlocks,
} from "./htmlBlockMap.js";

test("identifies paragraph and snaps bold span inside paragraph", () => {
  const html = "<p>Hello <strong>world</strong>!</p>";
  const { blocks, blockMap } = parseHTMLBlocks(html);
  assert.equal(blocks.length, 1);
  const p = blocks[0];
  assert.equal(p.tag, "p");
  assert.equal(p.start, 0);
  assert.equal(p.end, html.length);
  assert.equal(p.isComplete, true);

  // Selecting "world" (char offset 17..22) inside the bold span
  const snapped = snapHTMLBlocks({ start: -Infinity, end: Infinity, children: blocks }, { start: 17, end: 22 });
  assert.ok(snapped);
  assert.equal(snapped.from, 0);
  assert.equal(snapped.to, html.length);
  assert.equal(html.slice(snapped.from, snapped.to), "<p>Hello <strong>world</strong>!</p>");
});

test("distinguishes two paragraphs on the same source line", () => {
  const html = "<p>First paragraph</p><p>Second paragraph</p>";
  const { blocks } = parseHTMLBlocks(html);
  assert.equal(blocks.length, 2);

  const p1 = blocks[0];
  const p2 = blocks[1];
  assert.equal(p1.start, 0);
  assert.equal(p1.end, 22);
  assert.equal(html.slice(p1.start, p1.end), "<p>First paragraph</p>");

  assert.equal(p2.start, 22);
  assert.equal(p2.end, 45);
  assert.equal(html.slice(p2.start, p2.end), "<p>Second paragraph</p>");

  // Selecting inside second paragraph snaps ONLY to second paragraph
  const treeRoot = { start: -Infinity, end: Infinity, children: blocks };
  const snapped2 = snapHTMLBlocks(treeRoot, { start: 25, end: 31 });
  assert.ok(snapped2);
  assert.equal(snapped2.from, 22);
  assert.equal(snapped2.to, 45);
  assert.equal(html.slice(snapped2.from, snapped2.to), "<p>Second paragraph</p>");
});

test("nested list items snap progressively", () => {
  const html = "<ul><li>Item 1</li><li>Item 2<ul><li>Nested</li></ul></li></ul>";
  const { blocks } = parseHTMLBlocks(html);
  assert.equal(blocks.length, 1);
  const ul = blocks[0];
  assert.equal(ul.tag, "ul");
  assert.equal(ul.children.length, 2);

  const li1 = ul.children[0];
  const li2 = ul.children[1];
  assert.equal(html.slice(li1.start, li1.end), "<li>Item 1</li>");

  // Inside li2 there is a nested ul and nested li
  assert.equal(li2.children.length, 1);
  const nestedUl = li2.children[0];
  const nestedLi = nestedUl.children[0];
  assert.equal(html.slice(nestedLi.start, nestedLi.end), "<li>Nested</li>");

  // Selection inside "Nested" snaps to the nested <li>, not the outer <li> or <ul>
  const treeRoot = { start: -Infinity, end: Infinity, children: blocks };
  const nestedStart = html.indexOf("Nested");
  const snappedNested = snapHTMLBlocks(treeRoot, { start: nestedStart, end: nestedStart + 6 });
  assert.ok(snappedNested);
  assert.equal(html.slice(snappedNested.from, snappedNested.to), "<li>Nested</li>");
});

test("table cell snaps to its containing table row", () => {
  const html = "<table><tr><td>Cell 1</td><td>Cell 2</td></tr></table>";
  const { blocks } = parseHTMLBlocks(html);
  assert.equal(blocks.length, 1);
  const table = blocks[0];
  const tr = table.children[0];
  assert.equal(tr.tag, "tr");
  // td is not a block child; tr contains the cells
  assert.equal(tr.children.length, 0);

  const cell1Start = html.indexOf("Cell 1");
  const treeRoot = { start: -Infinity, end: Infinity, children: blocks };
  const snapped = snapHTMLBlocks(treeRoot, { start: cell1Start, end: cell1Start + 6 });
  assert.ok(snapped);
  assert.equal(html.slice(snapped.from, snapped.to), "<tr><td>Cell 1</td><td>Cell 2</td></tr>");
});

test("selection spanning adjacent blocks captures the single covering source range", () => {
  const html = "<p>Block 1</p>\n<p>Block 2</p>\n<p>Block 3</p>";
  const { blocks } = parseHTMLBlocks(html);
  assert.equal(blocks.length, 3);

  const treeRoot = { start: -Infinity, end: Infinity, children: blocks };
  // Span from inside Block 1 to inside Block 2
  const target = { start: 5, end: 20 };
  const snapped = snapHTMLBlocks(treeRoot, target);
  assert.ok(snapped);
  assert.equal(snapped.from, 0);
  assert.equal(snapped.to, blocks[1].end);
  assert.equal(html.slice(snapped.from, snapped.to), "<p>Block 1</p>\n<p>Block 2</p>");
});

test("exact preservation of Unicode, emoji, entities, and whitespace in source slice", () => {
  const html = "<p>Hello 🌍 &amp; <strong>café</strong>   multiple   spaces.</p>";
  const { blocks } = parseHTMLBlocks(html);
  assert.equal(blocks.length, 1);

  const treeRoot = { start: -Infinity, end: Infinity, children: blocks };
  const snapped = snapHTMLBlocks(treeRoot, { start: 10, end: 20 });
  assert.ok(snapped);
  const slice = html.slice(snapped.from, snapped.to);
  assert.equal(slice, html);
  // Preserves exact entity &amp; rather than decoded &, exact whitespace, exact emoji
  assert.ok(slice.includes("&amp;"));
  assert.ok(slice.includes("🌍"));
  assert.ok(slice.includes("   multiple   spaces."));
});

test("detects unclosed/incomplete HTML as isComplete: false and refuses to snap", () => {
  const incomplete1 = "<p>Hello <b>world";
  const res1 = parseHTMLBlocks(incomplete1);
  assert.equal(res1.blocks[0].isComplete, false);
  const snap1 = snapHTMLBlocks({ start: -Infinity, end: Infinity, children: res1.blocks }, { start: 5, end: 10 });
  assert.equal(snap1, null);

  const incomplete2 = "<div><p>Unclosed</div>";
  const res2 = parseHTMLBlocks(incomplete2);
  assert.equal(res2.blocks[0].isComplete, false); // inner p is unclosed
  const snap2 = snapHTMLBlocks({ start: -Infinity, end: Infinity, children: res2.blocks }, { start: 8, end: 12 });
  assert.equal(snap2, null);

  const incomplete3 = "<p>Unclosed paragraph";
  const res3 = parseHTMLBlocks(incomplete3);
  assert.equal(res3.blocks[0].isComplete, false);
  const snap3 = snapHTMLBlocks({ start: -Infinity, end: Infinity, children: res3.blocks }, { start: 3, end: 10 });
  assert.equal(snap3, null);
});

test("stamps preview HTML with dynamic attribute name without corrupting source", () => {
  const html = "<p>First</p><p class=\"second\">Second</p>";
  const { blocks } = parseHTMLBlocks(html);
  const attrName = "data-ctx-test123";
  const stamped = stampHTMLPreview(html, blocks, attrName);

  assert.match(stamped, /<p data-ctx-test123="0">First<\/p>/);
  assert.match(stamped, /<p class="second" data-ctx-test123="1">Second<\/p>/);
  // Source string remains unaffected
  assert.equal(html, "<p>First</p><p class=\"second\">Second</p>");
});

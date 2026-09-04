import { test } from "node:test";
import assert from "node:assert/strict";
import { createScrollMap } from "./scrollSync.js";

test("falls back to proportional scrolling when no document anchors exist", () => {
  const map = createScrollMap({ sourceMax: 400, previewMax: 1000 });

  assert.equal(map.sourceToPreview(100), 250);
  assert.equal(map.previewToSource(750), 300);
});

test("interpolates through document anchors in both directions", () => {
  const map = createScrollMap({
    sourceMax: 400,
    previewMax: 1000,
    anchors: [
      { source: 100, preview: 400 },
      { source: 300, preview: 700 },
    ],
  });

  assert.equal(map.sourceToPreview(50), 200);
  assert.equal(map.sourceToPreview(200), 550);
  assert.equal(map.previewToSource(550), 200);
  assert.equal(map.previewToSource(850), 350);
});

test("clamps offsets and handles a pane whose content does not scroll", () => {
  const map = createScrollMap({ sourceMax: 0, previewMax: 600 });

  assert.equal(map.sourceToPreview(200), 0);
  assert.equal(map.previewToSource(-20), 0);
  assert.equal(map.previewToSource(900), 0);
});

test("ignores malformed and non-monotonic anchors", () => {
  const map = createScrollMap({
    sourceMax: 400,
    previewMax: 1000,
    anchors: [
      { source: 100, preview: 400 },
      { source: 100, preview: 450 }, // nested block on the same Source line
      { source: 200, preview: 300 }, // reordered Preview block
      { source: Number.NaN, preview: 600 },
      { source: 500, preview: 900 }, // Source anchor cannot reach viewport top
    ],
  });

  assert.equal(map.sourceToPreview(100), 400);
  assert.equal(map.sourceToPreview(250), 700);
  assert.equal(map.previewToSource(400), 100);
});

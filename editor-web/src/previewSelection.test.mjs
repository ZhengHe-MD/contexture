import { test } from "node:test";
import assert from "node:assert/strict";
import { pollPreviewSelection } from "./previewSelection.js";

function previewSelection(range, { collapsed = false } = {}) {
  let removeAllRangesCalls = 0;
  return {
    isCollapsed: collapsed,
    rangeCount: 1,
    getRangeAt() {
      return range;
    },
    removeAllRanges() {
      removeAllRangesCalls += 1;
    },
    get removeAllRangesCalls() {
      return removeAllRangesCalls;
    },
  };
}

test("a changing Preview range is reported without deleting the browser range", () => {
  const startContainer = {};
  const endContainer = {};
  const firstRange = { startContainer, startOffset: 0, endContainer, endOffset: 2 };
  const expandedRange = { startContainer, startOffset: 0, endContainer, endOffset: 8 };
  const firstSelection = previewSelection(firstRange);
  const expandedSelection = previewSelection(expandedRange);
  const reported = [];
  const callbacks = {
    onRangeChanged: (range) => reported.push(range),
    onCollapsed: () => assert.fail("a non-empty range must not collapse"),
  };

  const firstPoint = pollPreviewSelection(firstSelection, null, callbacks);
  pollPreviewSelection(expandedSelection, firstPoint, callbacks);

  assert.deepEqual(reported, [firstRange, expandedRange]);
  assert.equal(firstSelection.removeAllRangesCalls, 0);
  assert.equal(expandedSelection.removeAllRangesCalls, 0);
});

test("the first collapsed tick after a Preview range collapses the mirrored visible Selection once", () => {
  const node = {};
  const range = { startContainer: node, startOffset: 0, endContainer: node, endOffset: 4 };
  const callbacks = {
    rangeChanges: 0,
    collapses: 0,
    onRangeChanged() {
      this.rangeChanges += 1;
    },
    onCollapsed() {
      this.collapses += 1;
    },
  };

  const selectedPoint = pollPreviewSelection(previewSelection(range), null, callbacks);
  const collapsedPoint = pollPreviewSelection(previewSelection(range, { collapsed: true }), selectedPoint, callbacks);
  pollPreviewSelection(previewSelection(range, { collapsed: true }), collapsedPoint, callbacks);

  assert.equal(callbacks.rangeChanges, 1);
  assert.equal(callbacks.collapses, 1);
  assert.equal(collapsedPoint, null);
});

// Reduces the sandboxed Preview's polled native Selection to the two events
// the editor cares about: a changed non-empty range, or the first collapse
// after one. Deliberately never mutates `selection`: deleting its ranges while
// a pointer drag is still in progress destroys WebKit's drag anchor and makes
// the remaining gesture select an unpredictable subset of blocks.
export function pollPreviewSelection(selection, previousPoint, callbacks) {
  if (!selection || selection.isCollapsed || selection.rangeCount === 0) {
    if (previousPoint) {
      callbacks.onCollapsed();
    }
    return null;
  }

  const domRange = selection.getRangeAt(0);
  const current = {
    startContainer: domRange.startContainer,
    startOffset: domRange.startOffset,
    endContainer: domRange.endContainer,
    endOffset: domRange.endOffset,
  };
  if (
    previousPoint &&
    previousPoint.startContainer === current.startContainer &&
    previousPoint.startOffset === current.startOffset &&
    previousPoint.endContainer === current.endContainer &&
    previousPoint.endOffset === current.endOffset
  ) {
    return previousPoint;
  }

  callbacks.onRangeChanged(domRange);
  return current;
}

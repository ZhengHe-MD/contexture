// A document-aware map between the Source and Preview scroll coordinate
// spaces. Callers provide matching pixel anchors (the Source position for a
// stamped line and that stamped block's Preview position); this module hides
// the edge handling, interpolation, and reverse mapping behind two methods.

const finite = (value) => Number.isFinite(value);
const clamp = (value, minimum, maximum) => Math.min(Math.max(value, minimum), maximum);

function directionalPoints(anchors, inputKey, outputKey, inputMax, outputMax) {
  const candidates = [
    { input: 0, output: 0 },
    ...anchors
      .filter((anchor) => finite(anchor[inputKey]) && finite(anchor[outputKey]))
      .map((anchor) => ({ input: anchor[inputKey], output: anchor[outputKey] }))
      // An anchor below either pane's maximum scroll position cannot be put
      // at the top of both viewports. The explicit end point below represents
      // that compressed tail without introducing a false plateau.
      .filter((point) => (
        point.input > 0
        && point.input < inputMax
        && point.output > 0
        && point.output < outputMax
      )),
    { input: inputMax, output: outputMax },
  ].sort((left, right) => left.input - right.input || left.output - right.output);

  const points = [];
  for (const candidate of candidates) {
    const previous = points.at(-1);
    if (previous && candidate.input === previous.input) {
      // Nested Preview blocks often start on the same Source line. Their
      // outermost (earliest) visual position is the stable anchor.
      previous.output = Math.min(previous.output, candidate.output);
      continue;
    }
    if (previous && candidate.output < previous.output) {
      // Source order and Preview order should agree. Ignore malformed or
      // unexpectedly reordered DOM anchors instead of making the map reverse.
      continue;
    }
    points.push(candidate);
  }
  return points;
}

function interpolate(value, points, maximum) {
  const bounded = clamp(finite(value) ? value : 0, 0, maximum);
  for (let index = 1; index < points.length; index += 1) {
    const lower = points[index - 1];
    const upper = points[index];
    if (bounded > upper.input) continue;
    const span = upper.input - lower.input;
    if (span <= 0) return upper.output;
    const progress = (bounded - lower.input) / span;
    return lower.output + progress * (upper.output - lower.output);
  }
  return points.at(-1)?.output ?? 0;
}

export function createScrollMap({ sourceMax, previewMax, anchors = [] }) {
  const safeSourceMax = finite(sourceMax) && sourceMax > 0 ? sourceMax : 0;
  const safePreviewMax = finite(previewMax) && previewMax > 0 ? previewMax : 0;
  const sourcePoints = directionalPoints(
    anchors,
    "source",
    "preview",
    safeSourceMax,
    safePreviewMax
  );
  // Build the reverse map from the already-normalized forward points. If the
  // caller ever hands us a reordered anchor, both directions must reject the
  // same anchor rather than each direction choosing a different path.
  const canonicalAnchors = sourcePoints.map((point) => ({
    source: point.input,
    preview: point.output,
  }));
  const previewPoints = directionalPoints(
    canonicalAnchors,
    "preview",
    "source",
    safePreviewMax,
    safeSourceMax
  );

  return {
    sourceToPreview(offset) {
      return interpolate(offset, sourcePoints, safeSourceMax);
    },
    previewToSource(offset) {
      return interpolate(offset, previewPoints, safePreviewMax);
    },
  };
}

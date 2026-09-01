// Source <-> Preview block mapping for synchronized Selection (issue #5).
//
// ## Mapping granularity: block-level, not inline-level
//
// Rendering is lossy (docs/architecture/selection-bridge.md "Selection
// acquisition"): a Preview selection must snap outward to the smallest set
// of *complete* nodes covering it, so published bytes are always parseable
// Markdown on their own. This module answers "which node(s)" using
// markdown-it's own block-level `token.map` (a `[startLine, endLine)` pair,
// 0-based, end-exclusive, already computed by the block parser for
// paragraph/heading/list-item/blockquote/table-row/fenced-code/etc. tokens)
// stamped onto the rendered HTML as a `data-src="start-end"` attribute.
//
// Deliberately NOT covered: inline-level nodes (a `**bold**` span, a link).
// Vanilla markdown-it does not attach source positions to inline tokens
// (`strong_open`, `link_open`, ...) at all -- confirmed empirically here,
// not assumed: parsing a document with bold text and a link and dumping
// every token's `.map` shows `null` for every inline-level token, only
// block-level tokens carry a range. A third-party package,
// `markdown-it-source-map` (npm, single maintainer, v0.1.1, published over
// a year ago with no notable adoption), was vetted by reading its actual
// source (12 lines) rather than trusting its README: it stamps
// `data-source-line` only on `token.level === 0` tokens whose type ends in
// `_open`, i.e. *top-level* blocks only -- strictly coarser than what this
// module does (this module stamps every block-level token, including
// nested ones: a selection inside one item of a nested list snaps to that
// `<li>`, not the whole outer list) -- and it does not touch inline tokens
// either, so it does not solve the inline case this ticket's acceptance
// criteria gestures at ("a Preview selection of part of a styled span snaps
// out to the whole node"). It was not adopted.
//
// Hand-rolling inline position tracking (re-scanning each inline token's
// `.content` against its containing block's source slice to locate
// `**...**`/`[...](...)` boundaries) was considered and rejected for this
// ticket: it is workable for the simple cases but fiddly and easy to get
// subtly wrong for nested spans, escaped markers, reference-style links,
// and repeated/ambiguous substrings within a block -- and a subtly wrong
// *inline* snap is a correctness risk against the one invariant that must
// never break (published bytes are always parseable), whereas a block-level
// floor is correct by construction: it is exactly the source lines
// markdown-it's own block parser already decided belong to that block.
//
// So: the floor this module snaps to is the innermost *block-level*
// container -- paragraph, heading, list item, blockquote, table row,
// fenced code block, thematic break, or a loose list item's own paragraph
// when the list is loose. A selection touching part of a styled span or a
// link snaps out to that containing block, which trivially satisfies "the
// link target is included" (the whole block's Markdown source, link syntax
// included, is a subset of what gets selected) and is always parseable.
// Two further, narrower gaps of the same kind:
//   - table cells (`<td>`/`<th>`) carry no `.map` of their own (verified
//     empirically: only `tr_open` does), so a selection inside one cell
//     snaps to the whole row, not just that cell.
//   - raw HTML blocks (a Document paragraph that is itself literal HTML)
//     are not stamped at all -- `html_block` does not render through the
//     attribute-bearing path the way `paragraph`/`heading`/etc. do.
//     Selections landing entirely inside one have no data-src ancestor and
//     are left unmapped (callers treat "no covering node found" as "do
//     nothing", never as license to guess or expand to the whole Document).

/// The markdown-it core rule that stamps every block-level token with its
/// own source line range. Applied once via `markdownRenderer.use(stampSourceRanges)`.
/// Pure with respect to this module (no DOM); depends only on markdown-it's
/// own token model.
export function stampSourceRanges(md) {
  md.core.ruler.push("contexture_stamp_source_ranges", (state) => {
    for (const token of state.tokens) {
      if (token.block && token.map) {
        token.attrSet("data-src", formatBlockRange({ start: token.map[0], end: token.map[1] }));
      }
    }
  });
}

/// `{start, end}` (0-based, end-exclusive line range, markdown-it's own
/// convention) -> the `data-src` attribute string.
export function formatBlockRange(range) {
  return `${range.start}-${range.end}`;
}

/// The inverse of `formatBlockRange`. Returns null for anything that is not
/// a well-formed `"<int>-<int>"` string rather than throwing, since callers
/// receive this from attribute values on Preview DOM content and a
/// malformed/missing one must be a safe no-op, never a crash.
export function parseBlockRange(value) {
  if (!value) return null;
  const match = /^(\d+)-(\d+)$/.exec(value);
  if (!match) return null;
  return { start: Number(match[1]), end: Number(match[2]) };
}

/// The core "smallest set of complete nodes" search, and the one piece of
/// this ticket's logic worth calling load-bearing: both directions
/// (Source -> Preview highlight, Preview -> Source selection) reduce to
/// this same question -- given a tree of ranged nodes and a target range,
/// which node(s) of the tree are the tightest complete covering set?
///
/// `node` is `{start, end, children}` where `children` is an array of
/// same-shaped nodes (evaluated lazily is fine -- a getter works) whose
/// ranges are assumed non-overlapping and to fall within `node`'s own
/// range (true for markdown-it block tokens: sibling blocks tile disjoint
/// line spans). `range` is `{start, end}` in the same 0-based,
/// end-exclusive units as `formatBlockRange`/`parseBlockRange`.
///
/// Precondition: `node` already contains `range` (callers seed the search
/// with a synthetic root of effectively unbounded range). Deliberately no
/// DOM dependency -- this is what the unit tests exercise directly with
/// plain objects.
///
/// Behavior:
///   - if exactly one child fully contains `range`, recurse into it (go as
///     small as the tree allows);
///   - otherwise, if one or more children intersect `range`, return all of
///     them (this *is* the "snap outward" step: covering a range that
///     spans two list items returns both `<li>` nodes, not their parent
///     `<ul>`, but also not just one of them);
///   - otherwise (no child data at this level -- a leaf, such as a
///     paragraph with only inline content, or table cells/raw HTML which
///     are never given children here), return `[node]` itself.
export function smallestCoveringNodes(node, range) {
  const children = node.children ? Array.from(node.children) : [];
  const containing = children.filter((child) => child.start <= range.start && range.end <= child.end);
  if (containing.length === 1) {
    return smallestCoveringNodes(containing[0], range);
  }
  const intersecting = children.filter((child) => child.start < range.end && range.start < child.end);
  if (intersecting.length === 0) {
    return [node];
  }
  return intersecting;
}

/// The `{start, end}` union of a non-empty list of ranged nodes -- the
/// "outward" part of "snaps outward to the smallest set of complete
/// nodes": once `smallestCoveringNodes` has picked a set of sibling nodes,
/// this is the merged range that spans all of them.
export function mergeNodeRanges(nodes) {
  const starts = nodes.map((node) => node.start);
  const ends = nodes.map((node) => node.end);
  return { start: Math.min(...starts), end: Math.max(...ends) };
}

/// A markdown-it block range (0-based, end-exclusive) -> CodeMirror's
/// 1-based, end-inclusive line numbers. Block-level source ranges are
/// always whole lines (Markdown's block grammar is line-oriented), so the
/// resulting CM line pair, sliced via `doc.line(n).from`/`.to`, is exactly
/// the node's Source text with no further character-level trimming needed.
export function cmLinesForBlockRange(range) {
  return { fromLine: range.start + 1, toLine: range.end };
}

/// The inverse of `cmLinesForBlockRange`: CodeMirror's 1-based, inclusive
/// line numbers -> a markdown-it-convention block range.
export function blockRangeForCmLines(fromLine, toLine) {
  return { start: fromLine - 1, end: toLine };
}

import { parser } from "@lezer/html";
import { smallestCoveringNodes, mergeNodeRanges } from "./blockMap.js";

export const VOID_TAGS = new Set([
  "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"
]);

export const INLINE_TAGS = new Set([
  "b", "strong", "i", "em", "u", "s", "strike", "del", "ins", "a", "span", "code",
  "mark", "small", "sub", "sup", "time", "abbr", "q", "cite", "dfn", "kbd", "var",
  "samp", "bdo", "bdi", "br", "img", "wbr"
]);

export function getTagName(node, html) {
  const openTag = node.firstChild;
  if (!openTag) return "";
  for (let c = openTag.firstChild; c; c = c.nextSibling) {
    if (c.name === "TagName") return html.slice(c.from, c.to).toLowerCase();
  }
  return "";
}

export function getCloseTagName(node, html) {
  for (let c = node.lastChild; c; c = c.prevSibling) {
    if (c.name === "CloseTag") {
      for (let sc = c.firstChild; sc; sc = sc.nextSibling) {
        if (sc.name === "TagName") return html.slice(sc.from, sc.to).toLowerCase();
      }
    }
  }
  return null;
}

export function checkElementComplete(node, html, errors) {
  const tag = getTagName(node, html);
  const closeTag = getCloseTagName(node, html);
  const isVoid = VOID_TAGS.has(tag);
  if (!isVoid && closeTag !== tag) return false;

  const hasErr = errors.some((e) => e.from >= node.from && e.to <= node.to);
  if (hasErr) return false;

  for (let c = node.firstChild; c; c = c.nextSibling) {
    if (c.name === "Element") {
      if (!checkElementComplete(c, html, errors)) return false;
    }
  }
  return true;
}

export function parseHTMLBlocks(html) {
  const tree = parser.parse(html);
  const blocks = [];
  const blockMap = new Map();
  let nextId = 0;

  const errors = [];
  tree.iterate({
    enter(node) {
      if (node.name === "⚠") {
        errors.push({ from: node.from, to: node.to });
      }
    },
  });

  function walk(node, parentBlock) {
    let currentBlock = parentBlock;
    if (node.name === "Element") {
      const tag = getTagName(node, html);
      const isNonBlock =
        INLINE_TAGS.has(tag) ||
        tag === "td" ||
        tag === "th" ||
        tag === "head" ||
        tag === "html" ||
        tag === "style" ||
        tag === "script" ||
        tag === "meta" ||
        tag === "link" ||
        tag === "base" ||
        tag === "title";

      if (!isNonBlock && tag !== "") {
        const openTag = node.firstChild;
        const openTagTo = openTag ? openTag.to : node.from;
        const isComplete = checkElementComplete(node, html, errors);
        const block = {
          id: nextId++,
          tag,
          start: node.from,
          end: node.to,
          openTagTo,
          isComplete,
          children: [],
          parent: parentBlock,
        };
        blockMap.set(block.id, block);
        if (parentBlock) {
          parentBlock.children.push(block);
        } else {
          blocks.push(block);
        }
        currentBlock = block;
      }
    }
    for (let child = node.firstChild; child; child = child.nextSibling) {
      walk(child, currentBlock);
    }
  }

  walk(tree.topNode, null);
  return { blocks, blockMap };
}

export function stampHTMLPreview(html, blocks, attrName) {
  // Flatten all blocks
  const allBlocks = [];
  function collect(list) {
    for (const b of list) {
      allBlocks.push(b);
      if (b.children && b.children.length > 0) {
        collect(b.children);
      }
    }
  }
  collect(blocks);

  // Sort back-to-front by openTagTo
  allBlocks.sort((a, b) => b.openTagTo - a.openTagTo);

  let stamped = html;
  for (const block of allBlocks) {
    const end = block.openTagTo;
    // Determine insertion position before > or />
    let insertAt = end;
    if (stamped.slice(end - 2, end) === "/>") {
      insertAt = end - 2;
    } else if (stamped.slice(end - 1, end) === ">") {
      insertAt = end - 1;
    }
    stamped = stamped.slice(0, insertAt) + ` ${attrName}="${block.id}"` + stamped.slice(insertAt);
  }

  return stamped;
}

export function snapHTMLBlocks(treeRoot, targetRange) {
  const covering = smallestCoveringNodes(treeRoot, targetRange);
  if (!covering || covering.length === 0) return null;

  // Verify all covering nodes are complete and finite
  for (const node of covering) {
    if (!node || node.isComplete === false) return null;
  }

  const snapped = mergeNodeRanges(covering);
  if (!Number.isFinite(snapped.start) || !Number.isFinite(snapped.end)) {
    return null;
  }
  return { from: snapped.start, to: snapped.end, nodes: covering };
}

import { load as parseYAML } from "js-yaml";

/// Extracts the small piece of Markdown front matter Contexture presents in
/// native chrome and blanks the complete leading front-matter block before it
/// reaches markdown-it. Blanking rather than slicing preserves Source line
/// numbers, which are the Preview Selection mapping authority.
export function parseMarkdownDocument(source) {
  const opening = /^(?:\uFEFF)?---[ \t]*(?:\r?\n)/.exec(source);
  if (!opening) return { title: null, previewSource: source };

  const closing = /^(?:---|\.\.\.)[ \t]*(?:\r?\n|$)/gm;
  closing.lastIndex = opening[0].length;
  const match = closing.exec(source);
  if (!match) return { title: null, previewSource: source };

  const metadataSource = source.slice(opening[0].length, match.index);
  let title = null;
  try {
    const metadata = parseYAML(metadataSource);
    if (metadata && typeof metadata === "object" && !Array.isArray(metadata)) {
      const candidate = metadata.title;
      if (typeof candidate === "string" && candidate.trim() !== "") {
        title = candidate.replace(/\s+/g, " ").trim();
      }
    }
  } catch {
    // A malformed metadata block remains hidden from Preview but does not get
    // to replace the safe native filename fallback.
  }
  const bodyStart = match.index + match[0].length;
  const blankFrontMatter = source.slice(0, bodyStart).replace(/[^\r\n]/g, " ");

  return {
    title,
    previewSource: blankFrontMatter + source.slice(bodyStart),
  };
}

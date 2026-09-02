import Foundation

/// Wraps Markdown-rendered HTML in a standalone document for the Preview
/// pane's sandboxed `<iframe>` (`srcdoc`, set from
/// `EditorViewController.editorBridgePreviewHTMLDidChange(_:)` — see
/// `editor-web/src/main.js`'s `window.__contexture_setPreviewHTML`).
///
/// This is the primary control named by docs/product.md's "Render the
/// Preview with JavaScript disabled and remote loads blocked": the Preview
/// iframe's `sandbox` attribute (see `editor-web/src/index.html`) has no
/// `allow-scripts`, so nothing this document contains can ever execute, and
/// the Content-Security-Policy below independently blocks every subresource
/// fetch — image, stylesheet, font, media, frame, XHR/fetch, prefetch, form
/// submission — from any origin other than `data:` (inline images) and
/// inline `<style>`/`style=` (this document's own table/code-block CSS).
/// `PreviewSanitizer` is applied on top as defense in depth; see its doc
/// comment for why that ordering is deliberate.
enum PreviewDocumentBuilder {
    /// Every directive is listed explicitly rather than relying on
    /// `default-src` to cover it, because two directives — `form-action`
    /// and `base-uri` — do **not** fall back to `default-src` per the CSP
    /// spec, so a `default-src 'none'` alone would silently leave a
    /// Document's raw `<form action="https://...">` or `<base href=
    /// "https://...">` unblocked.
    static let contentSecurityPolicy = [
        "default-src 'none'",
        "script-src 'none'",
        "img-src data:",
        "style-src 'unsafe-inline'",
        "font-src 'none'",
        "media-src 'none'",
        "object-src 'none'",
        "frame-src 'none'",
        "child-src 'none'",
        "worker-src 'none'",
        "connect-src 'none'",
        "form-action 'none'",
        "base-uri 'none'",
    ].joined(separator: "; ")

    /// Minimal styling so GFM tables and fenced code blocks are legible;
    /// `color-scheme: light dark` follows the writer's system appearance
    /// the same way `editor-web/src/editor.css` does for the Source pane.
    ///
    /// `.contexture-selected` is the synchronized-Selection highlight
    /// (issue #5): the outer trusted page's own script — never anything
    /// running inside this sandboxed document — adds/removes that class on
    /// the block-level element(s) `editor-web/src/blockMap.js`'s
    /// `data-src` attributes resolve a Source (or Preview) Selection to.
    /// It lives here, in the trusted wrapper this class builds, rather
    /// than in `bodyHTML`, so a Document could never smuggle a same-named
    /// class to spoof the highlight.
    private static let style = """
    :root { color-scheme: light dark; }
    body { margin: 0; padding: 12px 16px; font: 14px -apple-system, system-ui, sans-serif; line-height: 1.55; word-wrap: break-word; }
    img { max-width: 100%; }
    table { border-collapse: collapse; }
    th, td { border: 1px solid; padding: 4px 8px; }
    pre { overflow-x: auto; padding: 8px; background: rgba(128, 128, 128, 0.12); border-radius: 4px; }
    code { font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: 0.9em; }
    pre code { font-size: 1em; }
    .contexture-selected { background: rgba(255, 190, 40, 0.35); outline: 1px solid rgba(200, 140, 0, 0.6); outline-offset: 1px; border-radius: 3px; }
    """

    /// `bodyHTML` is untrusted Markdown-rendered output (see
    /// `editor-web/src/main.js`'s `markdownRenderer`, run with `html: true`
    /// so it preserves raw HTML the way real GFM does) — this function is
    /// the one place that both sanitizes it and puts it inside the CSP
    /// boundary above, so no caller can forget either step.
    static func buildDocument(bodyHTML: String) -> String {
        let sanitized = PreviewSanitizer.sanitize(bodyHTML)
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy)">
        <style>\(style)</style>
        </head>
        <body>\(sanitized)</body>
        </html>
        """
    }
}

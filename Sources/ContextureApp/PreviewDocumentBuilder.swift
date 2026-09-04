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
/// Before the CSP is applied, supported local raster images whose `src` is
/// relative to the Markdown Document are read from disk and converted to
/// `data:` URLs. This preserves the no-file/no-network runtime boundary while
/// making ordinary Markdown image paths useful. `PreviewSanitizer` is applied
/// on top as defense in depth; see its doc comment for why that ordering is
/// deliberate.
enum PreviewDocumentBuilder {
    /// A Preview is rebuilt frequently while typing, so do not let one image
    /// turn every keystroke into an unbounded file read and base64 allocation.
    static let maximumLocalImageBytes = 25 * 1_024 * 1_024

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
    .contexture-mermaid { display: flex; justify-content: center; max-width: 100%; margin: 1em 0; overflow: hidden; text-align: center; }
    .contexture-mermaid__open { display: block; color: inherit; text-decoration: none; }
    .contexture-mermaid img { display: block; width: auto; height: auto; max-width: 100%; max-height: 50vh; margin: 0 auto; object-fit: contain; }
    .contexture-mermaid__open[data-contexture-expandable="true"] { cursor: zoom-in; }
    .contexture-mermaid__open[data-contexture-expandable="true"]:focus-visible { outline: 3px solid AccentColor; outline-offset: 3px; }
    .contexture-mermaid-error { border-left: 3px solid #c33; color: #c33; white-space: pre-wrap; }
    .contexture-selected { background: rgba(255, 190, 40, 0.35); outline: 1px solid rgba(200, 140, 0, 0.6); outline-offset: 1px; border-radius: 3px; }
    """

    /// `bodyHTML` is untrusted Markdown-rendered output (see
    /// `editor-web/src/main.js`'s `markdownRenderer`, run with `html: true`
    /// so it preserves raw HTML the way real GFM does) — this function is
    /// the one place that both sanitizes it and puts it inside the CSP
    /// boundary above, so no caller can forget either step.
    static func buildDocument(bodyHTML: String, documentURL: URL? = nil) -> String {
        let withLocalImages = inlineLocalImages(in: bodyHTML, documentURL: documentURL)
        let sanitized = PreviewSanitizer.sanitize(withLocalImages)
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

    private static let imageTagExpression = try! NSRegularExpression(
        pattern: #"<img\b[^>]*>"#,
        options: [.caseInsensitive]
    )

    private static let sourceAttributeExpression = try! NSRegularExpression(
        pattern: #"\ssrc\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s\"'=<>`]+))"#,
        options: [.caseInsensitive]
    )

    private static let supportedRasterMIMETypes = [
        "png": "image/png",
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "gif": "image/gif",
        "webp": "image/webp",
        "avif": "image/avif",
        "bmp": "image/bmp",
        "tif": "image/tiff",
        "tiff": "image/tiff",
        "heic": "image/heic",
        "heif": "image/heif",
        "ico": "image/x-icon",
    ]

    /// Rewrites only relative `src` values on `<img>` elements. Absolute
    /// paths, file URLs, remote URLs, protocol-relative URLs, unsupported
    /// formats, missing files, directories, and oversized files remain
    /// untouched and are therefore blocked by the Preview CSP.
    private static func inlineLocalImages(in html: String, documentURL: URL?) -> String {
        guard let documentURL, documentURL.isFileURL else { return html }

        var result = html
        let fullRange = NSRange(result.startIndex..<result.endIndex, in: result)
        let matches = imageTagExpression.matches(in: result, range: fullRange)

        // Work backwards so replacing one tag cannot invalidate the ranges of
        // tags that precede it in the HTML string.
        for match in matches.reversed() {
            guard let tagRange = Range(match.range, in: result) else { continue }
            let tag = String(result[tagRange])
            let sourceRange = NSRange(tag.startIndex..<tag.endIndex, in: tag)
            guard let sourceMatch = sourceAttributeExpression.firstMatch(in: tag, range: sourceRange),
                  let valueRange = (1...3)
                    .map({ sourceMatch.range(at: $0) })
                    .first(where: { $0.location != NSNotFound }),
                  let swiftValueRange = Range(valueRange, in: tag) else { continue }

            let reference = decodeHTMLEntities(String(tag[swiftValueRange]))
            guard let dataURL = localImageDataURL(
                for: reference,
                relativeTo: documentURL.deletingLastPathComponent()
            ) else { continue }

            var rewrittenTag = tag
            rewrittenTag.replaceSubrange(swiftValueRange, with: dataURL)
            result.replaceSubrange(tagRange, with: rewrittenTag)
        }

        return result
    }

    private static func localImageDataURL(for reference: String, relativeTo directoryURL: URL) -> String? {
        guard !reference.isEmpty,
              !reference.hasPrefix("/"),
              !reference.hasPrefix("\\"),
              let components = URLComponents(string: reference),
              components.scheme == nil,
              components.host == nil,
              !components.path.isEmpty else { return nil }

        let decodedPath = components.percentEncodedPath.removingPercentEncoding ?? components.path
        guard !decodedPath.hasPrefix("/"), !decodedPath.hasPrefix("\\") else { return nil }
        let fileURL = URL(fileURLWithPath: decodedPath, relativeTo: directoryURL).standardizedFileURL
        guard let mimeType = supportedRasterMIMETypes[fileURL.pathExtension.lowercased()],
              let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let fileSize = values.fileSize,
              fileSize <= maximumLocalImageBytes,
              let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]),
              data.count <= maximumLocalImageBytes else { return nil }

        return "data:\(mimeType);base64,\(data.base64EncodedString())"
    }

    /// Markdown renderers entity-escape attribute values. Decode the small
    /// HTML entity set that can occur in a filesystem path before resolving
    /// it, including numeric entities used for non-ASCII punctuation.
    private static func decodeHTMLEntities(_ value: String) -> String {
        var result = value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")

        let numericEntity = try! NSRegularExpression(
            pattern: #"&#(?:x([0-9a-fA-F]+)|([0-9]+));"#
        )
        let matches = numericEntity.matches(
            in: result,
            range: NSRange(result.startIndex..<result.endIndex, in: result)
        )
        for match in matches.reversed() {
            guard let entityRange = Range(match.range, in: result) else { continue }
            let hexadecimalRange = match.range(at: 1)
            let decimalRange = match.range(at: 2)
            let radix: Int
            let digitsRange: NSRange
            if hexadecimalRange.location != NSNotFound {
                radix = 16
                digitsRange = hexadecimalRange
            } else {
                radix = 10
                digitsRange = decimalRange
            }
            guard let swiftDigitsRange = Range(digitsRange, in: result),
                  let scalarValue = UInt32(result[swiftDigitsRange], radix: radix),
                  let scalar = UnicodeScalar(scalarValue) else { continue }
            result.replaceSubrange(entityRange, with: String(scalar))
        }
        return result
    }
}

import Foundation

/// Strips the most dangerous constructs out of Markdown-rendered HTML before
/// it reaches the Preview pane.
///
/// This is defense in depth, **not** the primary control. The primary
/// control is the Preview iframe's `sandbox` attribute (no `allow-scripts`,
/// so nothing here executes regardless of what tags survive) plus the
/// Content-Security-Policy `PreviewDocumentBuilder` embeds in every Preview
/// document (which blocks every non-`data:` resource fetch, independent of
/// scripting). Both of those hold even if this sanitizer misses something.
///
/// It exists as a second, independent layer in case the sandbox/CSP layer
/// is ever misconfigured, disabled by a future refactor, or a WebKit
/// behaviour changes underneath it — and because regex-based sanitization
/// of arbitrary HTML can never be a complete parser, it does not attempt to
/// be one. It targets exactly the constructs GFM's raw-HTML passthrough can
/// smuggle a beacon or an active-content escape through: `<script>` and
/// friends, inline event-handler attributes, `javascript:`/`vbscript:`
/// URLs, and the click-time `ping` beacon.
enum PreviewSanitizer {
    /// Tags removed entirely, including their contents: each can either run
    /// (script), embed another active document (iframe/object/embed/applet),
    /// or influence the document in ways `PreviewDocumentBuilder`'s own head
    /// already owns (link/meta/base/style — a raw `<meta http-equiv=
    /// "Content-Security-Policy">` or `<base href>` from the Document must
    /// not be able to sit next to, or be confused with, the trusted CSP and
    /// document structure `PreviewDocumentBuilder` adds around this output).
    private static let removedTags = ["script", "iframe", "object", "embed", "applet", "link", "meta", "base", "style"]

    /// Attributes whose value can point at a resource or navigation target.
    /// `src` covers `<img>` too, but `data:` images are the whole point of
    /// "inline images render" (issue #4's acceptance criteria), so only the
    /// scriptable schemes below are stripped from it, not the attribute
    /// itself.
    private static let urlAttributes = ["href", "src", "action", "formaction", "poster", "background", "cite"]

    static func sanitize(_ html: String) -> String {
        var result = html

        for tag in removedTags {
            result = replacing(in: result, pattern: "<\(tag)\\b[^>]*>[\\s\\S]*?</\(tag)\\s*>", with: "")
            // A stray/unclosed opening tag (malformed or truncated HTML).
            result = replacing(in: result, pattern: "<\(tag)\\b[^>]*/?>", with: "")
        }

        // Inline event handlers (onload=, onerror=, onclick=, ...), any
        // quoting style.
        result = replacing(in: result, pattern: "\\s+on[a-zA-Z]+\\s*=\\s*\"[^\"]*\"", with: "")
        result = replacing(in: result, pattern: "\\s+on[a-zA-Z]+\\s*=\\s*'[^']*'", with: "")
        result = replacing(in: result, pattern: "\\s+on[a-zA-Z]+\\s*=\\s*[^\\s>]+", with: "")

        // javascript:/vbscript: URLs on anything that can point at one,
        // quoted or bare.
        let scheme = "(?:javascript|vbscript)\\s*:"
        let attributeGroup = "(?:\(urlAttributes.joined(separator: "|")))"
        result = replacing(
            in: result,
            pattern: "\\b\(attributeGroup)\\s*=\\s*\"\\s*\(scheme)[^\"]*\"",
            with: "",
            replacementBuilder: { attributeName(from: $0) }
        )
        result = replacing(
            in: result,
            pattern: "\\b\(attributeGroup)\\s*=\\s*'\\s*\(scheme)[^']*'",
            with: "",
            replacementBuilder: { attributeName(from: $0) }
        )
        result = replacing(
            in: result,
            pattern: "\\b\(attributeGroup)\\s*=\\s*\(scheme)[^\\s>]*",
            with: "",
            replacementBuilder: { attributeName(from: $0) }
        )

        // `ping` fires a network beacon on click, independent of JavaScript
        // — nothing about the sandbox or CSP above stops it, so it is
        // removed outright rather than relying on those layers.
        result = replacing(in: result, pattern: "\\s+ping\\s*=\\s*\"[^\"]*\"", with: "")
        result = replacing(in: result, pattern: "\\s+ping\\s*=\\s*'[^']*'", with: "")
        result = replacing(in: result, pattern: "\\s+ping\\s*=\\s*[^\\s>]+", with: "")

        return result
    }

    private static func attributeName(from match: String) -> String {
        let name = match.prefix { !$0.isWhitespace && $0 != "=" }
        return "\(name)=\"about:blank\""
    }

    private static func replacing(
        in text: String,
        pattern: String,
        with template: String,
        replacementBuilder: ((String) -> String)? = nil
    ) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return text }

        guard let replacementBuilder else {
            let range = NSRange(text.startIndex..., in: text)
            return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
        }

        var result = text
        while let match = regex.firstMatch(in: result, options: [], range: NSRange(result.startIndex..., in: result)),
              let range = Range(match.range, in: result) {
            result.replaceSubrange(range, with: replacementBuilder(String(result[range])))
        }
        return result
    }
}

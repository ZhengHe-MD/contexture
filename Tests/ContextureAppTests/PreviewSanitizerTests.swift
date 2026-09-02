import Foundation
import Testing
@testable import ContextureApp

// PreviewSanitizer is defense in depth for the Preview pane (see its doc
// comment and PreviewDocumentBuilder's): the primary control is the Preview
// iframe's sandbox (no allow-scripts) plus the CSP PreviewDocumentBuilder
// embeds, both of which these tests cannot exercise headlessly (no WebKit in
// `swift test`). These tests only cover the second, independent layer.
@Suite struct PreviewSanitizerTests {
    @Test func removesScriptTagsAndTheirContent() {
        let html = "<p>hi</p><script>alert(document.cookie)</script><p>bye</p>"
        let sanitized = PreviewSanitizer.sanitize(html)
        #expect(!sanitized.contains("<script"))
        #expect(!sanitized.contains("alert"))
        #expect(sanitized.contains("<p>hi</p>"))
        #expect(sanitized.contains("<p>bye</p>"))
    }

    @Test func removesScriptTagsCaseInsensitively() {
        let html = "<SCRIPT SRC=\"evil.js\"></SCRIPT>"
        let sanitized = PreviewSanitizer.sanitize(html)
        #expect(!sanitized.lowercased().contains("<script"))
    }

    @Test func removesUnclosedScriptTag() {
        // Malformed/truncated raw HTML shouldn't leave a dangling <script
        // ...> that some parser recovery path might still execute.
        let html = "<p>before</p><script>alert(1)"
        let sanitized = PreviewSanitizer.sanitize(html)
        #expect(!sanitized.contains("<script"))
    }

    @Test func removesIframeObjectEmbedAndAppletTags() {
        let html = """
        <iframe src="https://evil.example.com"></iframe>
        <object data="https://evil.example.com/x.swf"></object>
        <embed src="https://evil.example.com/x.swf">
        <applet code="Evil.class"></applet>
        """
        let sanitized = PreviewSanitizer.sanitize(html)
        #expect(!sanitized.contains("<iframe"))
        #expect(!sanitized.contains("<object"))
        #expect(!sanitized.contains("<embed"))
        #expect(!sanitized.contains("<applet"))
        #expect(!sanitized.contains("evil.example.com"))
    }

    @Test func removesLinkMetaBaseAndStyleTags() {
        // These could otherwise sit inside PreviewDocumentBuilder's <body>
        // and be confused with, or attempt to override, the trusted CSP
        // <meta> / document structure it builds around this output.
        let html = """
        <link rel="stylesheet" href="https://evil.example.com/x.css">
        <meta http-equiv="refresh" content="0;url=https://evil.example.com">
        <base href="https://evil.example.com/">
        <style>body::after { content: url(https://evil.example.com/beacon.png); }</style>
        """
        let sanitized = PreviewSanitizer.sanitize(html)
        #expect(!sanitized.contains("<link"))
        #expect(!sanitized.contains("<meta"))
        #expect(!sanitized.contains("<base"))
        #expect(!sanitized.contains("<style"))
        #expect(!sanitized.contains("evil.example.com"))
    }

    @Test func removesInlineEventHandlerAttributesRegardlessOfQuoting() {
        let doubleQuoted = "<img src=\"data:image/png;base64,AAAA\" onerror=\"alert(1)\">"
        let singleQuoted = "<img src='data:image/png;base64,AAAA' onerror='alert(1)'>"
        let unquoted = "<body onload=alert(1)>"
        #expect(!PreviewSanitizer.sanitize(doubleQuoted).lowercased().contains("onerror"))
        #expect(!PreviewSanitizer.sanitize(singleQuoted).lowercased().contains("onerror"))
        #expect(!PreviewSanitizer.sanitize(unquoted).lowercased().contains("onload"))
    }

    @Test func removesVariousEventHandlerNames() {
        let html = "<div onclick=\"a()\" onmouseover=\"b()\" onfocus=\"c()\">text</div>"
        let sanitized = PreviewSanitizer.sanitize(html)
        #expect(!sanitized.lowercased().contains("onclick"))
        #expect(!sanitized.lowercased().contains("onmouseover"))
        #expect(!sanitized.lowercased().contains("onfocus"))
        #expect(sanitized.contains(">text</div>"))
    }

    @Test func doesNotMatchAttributesThatMerelyContainOnAsASubstring() {
        // Regression guard for the "on" prefix regex: an attribute like
        // data-iconload must survive since it does not start with "on".
        let html = "<div data-iconload=\"keep-me\">text</div>"
        let sanitized = PreviewSanitizer.sanitize(html)
        #expect(sanitized.contains("data-iconload=\"keep-me\""))
    }

    @Test func neutralizesJavascriptURLsInHref() {
        let doubleQuoted = "<a href=\"javascript:alert(1)\">click</a>"
        let singleQuoted = "<a href='javascript:alert(1)'>click</a>"
        let unquoted = "<a href=javascript:alert(1)>click</a>"
        for html in [doubleQuoted, singleQuoted, unquoted] {
            let sanitized = PreviewSanitizer.sanitize(html)
            #expect(!sanitized.lowercased().contains("javascript:"), "\(sanitized)")
        }
    }

    @Test func neutralizesVbscriptURLs() {
        let html = "<a href=\"vbscript:msgbox(1)\">click</a>"
        let sanitized = PreviewSanitizer.sanitize(html)
        #expect(!sanitized.lowercased().contains("vbscript:"))
    }

    @Test func neutralizesJavascriptURLsAcrossAllTrackedAttributes() {
        let html = """
        <form action="javascript:alert(1)"><button formaction="javascript:alert(2)">go</button></form>
        <video poster="javascript:alert(3)"></video>
        <blockquote cite="javascript:alert(4)">quote</blockquote>
        """
        let sanitized = PreviewSanitizer.sanitize(html)
        #expect(!sanitized.lowercased().contains("javascript:"))
    }

    @Test func doesNotStripDataURLImageSources() {
        // "inline images render" (issue #4 acceptance criteria) depends on
        // data: URIs surviving sanitization even though src is a tracked
        // attribute for other schemes.
        let html = "<img src=\"data:image/png;base64,AAAA\" alt=\"a pixel\">"
        let sanitized = PreviewSanitizer.sanitize(html)
        #expect(sanitized.contains("src=\"data:image/png;base64,AAAA\""))
    }

    @Test func doesNotStripInertMermaidSVGImageSources() {
        let html = "<img src=\"data:image/svg+xml;base64,PHN2Zz48L3N2Zz4=\" alt=\"Mermaid diagram\">"
        let sanitized = PreviewSanitizer.sanitize(html)
        #expect(sanitized == html)
    }

    @Test func removesPingAttribute() {
        let html = "<a href=\"/local\" ping=\"https://evil.example.com/beacon\">click</a>"
        let sanitized = PreviewSanitizer.sanitize(html)
        #expect(!sanitized.contains("ping="))
        #expect(sanitized.contains("href=\"/local\""))
    }

    @Test func leavesOrdinaryGFMOutputUnchanged() {
        // markdown-it output for tables, fenced code, and a data: image —
        // the sanitizer must not damage any of the content issue #4
        // requires to render.
        let html = """
        <table>
        <thead><tr><th>a</th><th>b</th></tr></thead>
        <tbody><tr><td>1</td><td>2</td></tr></tbody>
        </table>
        <pre><code class="language-js">const x = 1;
        </code></pre>
        <p><img src="data:image/png;base64,AAAA" alt="alt"></p>
        """
        #expect(PreviewSanitizer.sanitize(html) == html)
    }
}

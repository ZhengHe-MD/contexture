import Foundation
import Testing
@testable import ContextureApp

// These tests cover the parts of Preview isolation that are pure string
// construction and can run headlessly. They cannot exercise the parts that
// actually enforce the isolation at runtime — the iframe `sandbox` attribute
// (editor-web/src/index.html) and WebKit's own CSP enforcement — since
// `swift test` has no WebKit. See the top-level report for how that half was
// reasoned about instead.
@Suite struct PreviewDocumentBuilderTests {
    @Test func embedsAContentSecurityPolicyMetaTag() {
        let document = PreviewDocumentBuilder.buildDocument(bodyHTML: "<p>hello</p>")
        #expect(document.contains("<meta http-equiv=\"Content-Security-Policy\""))
    }

    @Test func cspBlocksEverythingByDefaultAndOnlyAllowsDataImagesAndInlineStyle() {
        let csp = PreviewDocumentBuilder.contentSecurityPolicy
        #expect(csp.contains("default-src 'none'"))
        #expect(csp.contains("script-src 'none'"))
        #expect(csp.contains("img-src data:"))
        #expect(csp.contains("style-src 'unsafe-inline'"))
        // form-action and base-uri do not fall back to default-src per the
        // CSP spec, so they must be listed explicitly.
        #expect(csp.contains("form-action 'none'"))
        #expect(csp.contains("base-uri 'none'"))
        // No directive anywhere in the policy names an http(s) origin.
        #expect(!csp.contains("http:"))
        #expect(!csp.contains("https:"))
        #expect(!csp.contains("*"))
    }

    @Test func sanitizesBodyHTMLBeforeEmbeddingIt() {
        let document = PreviewDocumentBuilder.buildDocument(
            bodyHTML: "<p>hi</p><script>alert(document.cookie)</script>"
        )
        #expect(!document.contains("<script"))
        #expect(!document.contains("alert"))
        #expect(document.contains("<p>hi</p>"))
    }

    @Test func preservesGFMTablesFencedCodeAndInlineImages() {
        let bodyHTML = """
        <table><thead><tr><th>a</th></tr></thead><tbody><tr><td>1</td></tr></tbody></table>
        <pre><code class="language-js">const x = 1;</code></pre>
        <p><img src="data:image/png;base64,AAAA" alt="alt"></p>
        """
        let document = PreviewDocumentBuilder.buildDocument(bodyHTML: bodyHTML)
        #expect(document.contains("<table>"))
        #expect(document.contains("<pre><code"))
        #expect(document.contains("data:image/png;base64,AAAA"))
    }

    @Test func embedsTheSynchronizedSelectionHighlightStyle() {
        // issue #5: the outer trusted page's own script (never anything
        // running inside this sandboxed document) toggles this class on the
        // block-level element(s) a Selection maps to. It must come from
        // this trusted wrapper, not from bodyHTML, so a Document's own
        // content could never spoof it by declaring a same-named class.
        let document = PreviewDocumentBuilder.buildDocument(bodyHTML: "<p>hi</p>")
        #expect(document.contains(".contexture-selected"))
    }

    @Test func producesAWellFormedStandaloneDocument() {
        let document = PreviewDocumentBuilder.buildDocument(bodyHTML: "<p>hi</p>")
        #expect(document.hasPrefix("<!doctype html>"))
        #expect(document.contains("<html>"))
        #expect(document.contains("<head>"))
        #expect(document.contains("<body>"))
        #expect(document.contains("</html>"))
    }
}

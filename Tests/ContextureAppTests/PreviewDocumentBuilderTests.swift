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

    @Test func inlinesImagePathsRelativeToTheMarkdownDocument() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("contexture-preview-\(UUID().uuidString)", isDirectory: true)
        let assets = directory.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let imageURL = assets.appendingPathComponent("pixel.png")
        try Data([0x01, 0x02, 0x03]).write(to: imageURL)
        let markdownURL = directory.appendingPathComponent("notes.md")

        let document = PreviewDocumentBuilder.buildDocument(
            bodyHTML: #"<p><img src="assets/pixel.png" alt="pixel"></p>"#,
            documentURL: markdownURL
        )

        #expect(document.contains(#"src="data:image/png;base64,AQID""#))
        #expect(!document.contains(#"src="assets/pixel.png""#))
    }

    @Test func keepsNonLocalAndAlreadyInlinedImageSourcesForTheCSPToHandle() {
        let markdownURL = URL(fileURLWithPath: "/tmp/notes.md")
        let sources = [
            "https://example.com/pixel.png",
            "//example.com/pixel.png",
            "/tmp/pixel.png",
            "file:///tmp/pixel.png",
            "data:image/png;base64,AQID",
        ]

        for source in sources {
            let bodyHTML = #"<p><img src="\#(source)" alt="pixel"></p>"#
            let document = PreviewDocumentBuilder.buildDocument(
                bodyHTML: bodyHTML,
                documentURL: markdownURL
            )
            #expect(document.contains(#"src="\#(source)""#), "\(source)")
        }
    }

    @Test func leavesMissingAndUnsupportedRelativeImagesBlocked() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("contexture-preview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data("<svg/>".utf8).write(to: directory.appendingPathComponent("diagram.svg"))
        let markdownURL = directory.appendingPathComponent("notes.md")
        let bodyHTML = #"<img src="missing.png"><img src="diagram.svg">"#
        let document = PreviewDocumentBuilder.buildDocument(
            bodyHTML: bodyHTML,
            documentURL: markdownURL
        )

        #expect(document.contains(#"src="missing.png""#))
        #expect(document.contains(#"src="diagram.svg""#))
    }

    @Test func doesNotConfuseDataSourceWithTheImageSource() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("contexture-preview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data([0x01, 0x02, 0x03]).write(to: directory.appendingPathComponent("pixel.png"))
        let document = PreviewDocumentBuilder.buildDocument(
            bodyHTML: #"<img data-src="1-2" src="pixel.png">"#,
            documentURL: directory.appendingPathComponent("notes.md")
        )

        #expect(document.contains(#"data-src="1-2""#))
        #expect(document.contains(#"src="data:image/png;base64,AQID""#))
    }

    @Test func preservesInertMermaidImagesAndTheirAtomicSourceRange() {
        let bodyHTML = """
        <figure class="contexture-mermaid" data-src="2-6">
        <img src="data:image/svg+xml;base64,PHN2Zz48L3N2Zz4=" alt="A to B">
        </figure>
        """
        let document = PreviewDocumentBuilder.buildDocument(bodyHTML: bodyHTML)
        #expect(document.contains("class=\"contexture-mermaid\""))
        #expect(document.contains("data-src=\"2-6\""))
        #expect(document.contains("data:image/svg+xml;base64,PHN2Zz48L3N2Zz4="))
        #expect(document.contains("alt=\"A to B\""))
        #expect(document.contains(".contexture-mermaid img"))
    }

    @Test func sizesDiagramsToTheirContentWithAHalfViewportHeightLimit() {
        let document = PreviewDocumentBuilder.buildDocument(bodyHTML: "<p>hi</p>")
        #expect(document.contains("display: flex"))
        #expect(document.contains("max-width: 100%"))
        #expect(document.contains("max-height: 50vh"))
        #expect(document.contains("cursor: zoom-in"))
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

    @Test func buildDocumentForFullHTMLPagePreservesAuthoredCSSAndLayout() {
        let authored = """
        <!DOCTYPE html>
        <html>
        <head>
        <title>Test Page</title>
        <style>body { background: navy; margin: 40px; } h1 { font-family: serif; }</style>
        </head>
        <body>
        <h1>Title</h1>
        <p>Text</p>
        </body>
        </html>
        """
        let doc = PreviewDocumentBuilder.buildDocument(bodyHTML: authored, format: .html)
        #expect(doc.contains("background: navy"))
        #expect(doc.contains("margin: 40px"))
        #expect(doc.contains("font-family: serif"))
        #expect(doc.contains(".contexture-selected"))
        #expect(doc.contains("Content-Security-Policy"))
        #expect(doc.contains("<meta charset=\"utf-8\">"))
    }

    @Test func buildDocumentForFullHTMLPageDoesNotImposeMarkdownTypography() {
        let authored = "<!DOCTYPE html><html><head></head><body><p>Text</p></body></html>"
        let doc = PreviewDocumentBuilder.buildDocument(bodyHTML: authored, format: .html)
        // Markdown style specifies padding: 12px 16px and table border-collapse;
        // full HTML page must not have Markdown's body style injected into it.
        #expect(!doc.contains("border-collapse: collapse"))
    }

    @Test func buildDocumentForHTMLFragmentAppliesReadableDefaults() {
        let fragment = "<h2>Fragment Title</h2><p>Fragment text.</p>"
        let doc = PreviewDocumentBuilder.buildDocument(bodyHTML: fragment, format: .html)
        #expect(doc.contains("<!doctype html>"))
        #expect(doc.contains("<html>"))
        #expect(doc.contains("<head>"))
        #expect(doc.contains("Content-Security-Policy"))
        #expect(doc.contains(".contexture-selected"))
        #expect(doc.contains("padding: 12px 16px"))
        #expect(doc.contains("<h2>Fragment Title</h2><p>Fragment text.</p>"))
    }

    @Test func buildDocumentForFullHTMLPageWithoutHeadDoesNotInjectIntoHeader() {
        let authored = "<!DOCTYPE html><html><body><header>Site Header</header><p>Text</p></body></html>"
        let doc = PreviewDocumentBuilder.buildDocument(bodyHTML: authored, format: .html)
        #expect(doc.contains("<head>"))
        #expect(!doc.contains("<header>\n<meta"))
        #expect(doc.contains("<header>Site Header</header>"))
    }
}

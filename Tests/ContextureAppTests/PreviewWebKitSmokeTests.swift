import Foundation
import Testing
import WebKit
@testable import ContextureApp

@Suite(.serialized)
@MainActor
struct PreviewWebKitSmokeTests {
    private class NavigationHelper: NSObject, WKNavigationDelegate {
        var continuation: CheckedContinuation<Void, Error>?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            continuation?.resume()
            continuation = nil
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    private func loadHTML(_ html: String, in webView: WKWebView) async throws {
        let helper = NavigationHelper()
        webView.navigationDelegate = helper
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            helper.continuation = continuation
            webView.loadHTMLString(html, baseURL: URL(string: "about:blank"))
        }
    }

    @Test func previewRendersAuthoredCSS() async throws {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: config)

        let authoredHTML = "<style>h1 { color: rgb(255, 0, 0); }</style><h1>Test</h1>"
        let fullDocument = PreviewDocumentBuilder.buildDocument(bodyHTML: authoredHTML, format: .html)

        try await loadHTML(fullDocument, in: webView)

        let color = try await webView.evaluateJavaScript(
            "window.getComputedStyle(document.querySelector('h1')).color"
        ) as? String
        #expect(color == "rgb(255, 0, 0)")
    }

    @Test func previewAppliesContextureSelectedHighlight() async throws {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: config)

        let authoredHTML = "<p class=\"contexture-selected\">Selected paragraph</p>"
        let fullDocument = PreviewDocumentBuilder.buildDocument(bodyHTML: authoredHTML, format: .html)

        try await loadHTML(fullDocument, in: webView)

        let outlineStyle = try await webView.evaluateJavaScript(
            "window.getComputedStyle(document.querySelector('.contexture-selected')).outlineStyle"
        ) as? String
        #expect(outlineStyle == "solid")

        let outlineWidth = try await webView.evaluateJavaScript(
            "window.getComputedStyle(document.querySelector('.contexture-selected')).outlineWidth"
        ) as? String
        #expect(outlineWidth == "1px")

        let borderRadius = try await webView.evaluateJavaScript(
            "window.getComputedStyle(document.querySelector('.contexture-selected')).borderRadius"
        ) as? String
        #expect(borderRadius == "3px")
    }

    @Test func previewBlocksInlineScriptExecutionViaSandbox() async throws {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: config)

        // The Preview pane in Contexture (ADR-0002) is hosted in a sandboxed <iframe>
        // without allow-scripts. Verify that WebKit runtime blocks script execution.
        let hostHTML = """
        <!doctype html>
        <html>
        <body>
        <iframe id="preview" sandbox="allow-same-origin" srcdoc="<script>window.parent.__scriptRan = true;</script><p>Hello</p>"></iframe>
        </body>
        </html>
        """
        try await loadHTML(hostHTML, in: webView)

        try await Task.sleep(nanoseconds: 100_000_000)

        let scriptRan = try await webView.evaluateJavaScript("window.__scriptRan")
        #expect(scriptRan == nil)
    }
}

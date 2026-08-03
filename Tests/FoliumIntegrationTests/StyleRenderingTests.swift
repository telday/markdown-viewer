import AppKit
import Testing
import WebKit
@testable import Folium

/// Seam tests for the styling added in issue #3. These deliberately do **not**
/// re-assert GitHub's CSS *values* (border widths, hex colors) — that's the
/// upstream stylesheet's own responsibility and would just pin us to it. They
/// verify the parts *we* own: that our document actually wires the stylesheet up
/// so it takes effect on the DOM our renderer produces, and that our dark-mode
/// plumbing (the `color-scheme` meta tag + WKWebView appearance) really flips
/// the rendering. Both are silent failure modes that string assertions miss.
///
/// Runs in a real WKWebView, so it lives in the integration target rather than
/// the unit/logic layer.
@MainActor
struct StyleRenderingTests {
    /// The stylesheet is a no-op unless its selectors match the class our wrapper
    /// applies *and* the HTML shape cmark-gfm emits. This drives the real
    /// render→wrap path and confirms styling reaches both a heading and a task
    /// list item (whose `:has()` selector matches our class-less `<li>`).
    @Test func stylesheetAppliesToTheRenderedDocument() async throws {
        let body = MarkdownRenderer.renderHTML(from: "# Title\n\n- [ ] todo\n- [x] done")
        let webView = try await loadedWebView(html: MarkdownPage.html(bodyHTML: body))

        // `.markdown-body h1` gives every h1 a bottom border: proves the wrapper's
        // class matches the sheet's selectors (drift here silently unstyles all).
        let headingBorder = try await computedStyle(webView, selector: "h1", property: "border-bottom-style")
        #expect(headingBorder == "solid")

        // Our `:has(> input[type=checkbox])` selector hides the bullet on the
        // class-less `<li>` cmark-gfm emits: proves selectors match the real DOM.
        let taskBullet = try await computedStyle(
            webView, selector: "li:has(input)", property: "list-style-type"
        )
        #expect(taskBullet == "none")
    }

    /// Dark mode is our integration decision, not GitHub's CSS: WKWebView only
    /// resolves `prefers-color-scheme` because of our `color-scheme` meta tag and
    /// the view's effective appearance. Assert the canvas background actually
    /// differs between the two system appearances (not the specific hex values).
    @Test func backgroundFollowsSystemAppearance() async throws {
        let page = MarkdownPage.html(bodyHTML: "<p>hi</p>")

        let light = try await loadedWebView(html: page, appearance: .aqua)
        let dark = try await loadedWebView(html: page, appearance: .darkAqua)

        let lightBackground = try await computedStyle(light, selector: "body", property: "background-color")
        let darkBackground = try await computedStyle(dark, selector: "body", property: "background-color")

        #expect(lightBackground != darkBackground)
        // Sanity that the media query resolved the way the appearance implies,
        // without pinning the exact palette values the upstream sheet owns.
        #expect(lightBackground == "rgb(255, 255, 255)")
        #expect(darkBackground != "rgb(255, 255, 255)")
    }

    // MARK: - Helpers

    private func loadedWebView(
        html: String,
        appearance: NSAppearance.Name = .aqua
    ) async throws -> WKWebView {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1012, height: 800))
        webView.appearance = NSAppearance(named: appearance)
        let waiter = NavigationWaiter()
        webView.navigationDelegate = waiter
        webView.loadHTMLString(html, baseURL: nil)
        await waiter.waitUntilFinished()
        return webView
    }

    private func computedStyle(
        _ webView: WKWebView,
        selector: String,
        property: String
    ) async throws -> String {
        let script = "getComputedStyle(document.querySelector(\"\(selector)\")).getPropertyValue(\"\(property)\")"
        let result = try await webView.evaluateJavaScript(script)
        return (result as? String) ?? ""
    }
}

/// Bridges `WKNavigationDelegate`'s completion callback to `async/await` so a
/// test can wait for `loadHTMLString` to finish before reading computed styles.
@MainActor
private final class NavigationWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var finished = false

    func waitUntilFinished() async {
        if finished { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished = true
        continuation?.resume()
        continuation = nil
    }
}

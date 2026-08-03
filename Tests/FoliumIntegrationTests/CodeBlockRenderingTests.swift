import AppKit
import Testing
import WebKit
@testable import Folium

/// Seam tests for the syntax highlighting and copy-to-clipboard behavior added
/// in issue #4. As with `StyleRenderingTests`, these deliberately avoid
/// re-asserting facts that belong to a dependency: highlight.js's own
/// tokenization (which class gets which color) is its job, not ours — we only
/// check that our vendored script actually ran against the DOM our renderer +
/// decorator produce (the `hljs` class lands on the real `<code>` element).
///
/// The copy tests click the real button and read the real system pasteboard
/// (`NSPasteboard.general`) rather than stubbing `navigator.clipboard`:
/// `CodeBlockScript` copies via `document.execCommand("copy")`, since
/// `navigator.clipboard` is unavailable in a `loadHTMLString(baseURL: nil)`
/// WKWebView (opaque origin, no secure context) — there's no Clipboard API
/// call to intercept, so the general pasteboard is the only observable seam.
/// Save/restore around each test so a local `swift test` run doesn't clobber
/// whatever the developer actually has copied.
///
/// Runs in a real WKWebView, so it lives in the integration target.
@MainActor
struct CodeBlockRenderingTests {
    @Test func highlightJSRunsAgainstTheRenderedCodeBlock() async throws {
        let body = MarkdownRenderer.renderHTML(from: "```swift\nlet x = 1\n```")
        let webView = try await loadedWebView(html: MarkdownPage.html(bodyHTML: body))

        // highlightAll() adds the "hljs" class to every element it processes;
        // seeing it on our actual DOM proves the vendored script executed and
        // found the code block, not just that the library loaded in isolation.
        let result = try await webView.evaluateJavaScript(
            "document.querySelector('code').classList.contains('hljs')"
        )
        #expect(result as? Bool == true)
    }

    /// Every other copy-button test drives it via `querySelector(...).click()`,
    /// which succeeds regardless of whether a human could actually see or hit
    /// the button — a `display: none` or zero-size regression would pass all
    /// of them. This is the tier-2 computed-style check (same pattern as
    /// `StyleRenderingTests`) that closes that gap: real geometry/visibility
    /// off the real DOM, not the exact pixel values `CodeBlockStylesheet` owns.
    @Test func copyButtonIsVisibleAndClickable() async throws {
        let body = MarkdownRenderer.renderHTML(from: "```swift\nlet x = 1\n```")
        let webView = try await loadedWebView(html: MarkdownPage.html(bodyHTML: body))

        let script = """
        (function () {
          var button = document.querySelector(".copy-button");
          var style = getComputedStyle(button);
          var rect = button.getBoundingClientRect();
          return {
            display: style.display,
            visibility: style.visibility,
            cursor: style.cursor,
            width: rect.width,
            height: rect.height
          };
        })();
        """
        let result = try await webView.evaluateJavaScript(script)
        let geometry = try #require(result as? [String: Any])

        #expect(geometry["display"] as? String != "none")
        #expect(geometry["visibility"] as? String != "hidden")
        // Our own rule, not a browser default — proves CodeBlockStylesheet
        // actually reached this element.
        #expect(geometry["cursor"] as? String == "pointer")
        #expect((geometry["width"] as? Double ?? 0) > 0)
        #expect((geometry["height"] as? Double ?? 0) > 0)
    }

    @Test func copyButtonCopiesTheBlocksRawTextToTheSystemPasteboard() async throws {
        let previousPasteboardContents = NSPasteboard.general.string(forType: .string)
        defer { restorePasteboard(previousPasteboardContents) }

        let body = MarkdownRenderer.renderHTML(from: "```swift\nlet x = 1\n```")
        let webView = try await loadedWebView(html: MarkdownPage.html(bodyHTML: body))

        NSPasteboard.general.clearContents()
        _ = try await webView.evaluateJavaScript("document.querySelector('.copy-button').click()")

        #expect(NSPasteboard.general.string(forType: .string) == "let x = 1\n")
    }

    @Test func copyButtonShowsConfirmationAfterClicking() async throws {
        let previousPasteboardContents = NSPasteboard.general.string(forType: .string)
        defer { restorePasteboard(previousPasteboardContents) }

        let body = MarkdownRenderer.renderHTML(from: "```swift\nlet x = 1\n```")
        let webView = try await loadedWebView(html: MarkdownPage.html(bodyHTML: body))

        _ = try await webView.evaluateJavaScript("document.querySelector('.copy-button').click()")
        let buttonText = try await webView.evaluateJavaScript("document.querySelector('.copy-button').textContent")

        #expect(buttonText as? String == "Copied!")
    }

    // MARK: - Helpers

    private func restorePasteboard(_ contents: String?) {
        NSPasteboard.general.clearContents()
        if let contents {
            NSPasteboard.general.setString(contents, forType: .string)
        }
    }

    private func loadedWebView(html: String) async throws -> WKWebView {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1012, height: 800))
        let waiter = NavigationWaiter()
        webView.navigationDelegate = waiter
        webView.loadHTMLString(html, baseURL: nil)
        await waiter.waitUntilFinished()
        return webView
    }
}

/// Bridges `WKNavigationDelegate`'s completion callback to `async/await` so a
/// test can wait for `loadHTMLString` to finish before running script against
/// the loaded document. Duplicated from `StyleRenderingTests` — both files are
/// small `@MainActor` test-only helpers, and sharing it isn't worth a new
/// production type for two call sites.
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

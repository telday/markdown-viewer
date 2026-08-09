import SwiftUI
import WebKit

/// Displays rendered Markdown HTML in a `WKWebView` (ADR 0001).
///
/// Loads `MarkdownPage`'s static shell exactly once via `loadFileURL` (the
/// only WKWebView API that grants a page read access to sibling local
/// files — `loadHTMLString(_:baseURL:)` does not, despite taking a
/// `baseURL`: WebKit gives every `file://` resource its own origin, and a
/// plain `baseURL` only resolves relative URLs, it doesn't grant access to
/// what they point at). Every subsequent `bodyHTML` change is pushed in via
/// `evaluateJavaScript` instead of a reload — see `MarkdownWebViewState` for
/// why reloading on every change would be prohibitively expensive.
struct MarkdownWebView: NSViewRepresentable {
    let bodyHTML: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.loadFileURL(MarkdownPage.pageURL, allowingReadAccessTo: MarkdownPage.resourceBaseURL)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if let ready = context.coordinator.state.render(bodyHTML: bodyHTML) {
            webView.evaluateJavaScript(MarkdownPage.renderBodyScript(bodyHTML: ready))
        }
    }

    /// Bridges the shell's one-time `didFinish` navigation callback to
    /// `MarkdownWebViewState`, and delivers whatever content was queued
    /// while it was still loading.
    final class Coordinator: NSObject, WKNavigationDelegate {
        let state = MarkdownWebViewState()

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let queued = state.shellDidFinishLoading() else { return }
            webView.evaluateJavaScript(MarkdownPage.renderBodyScript(bodyHTML: queued))
        }
    }
}

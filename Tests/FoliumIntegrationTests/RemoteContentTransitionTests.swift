import AppKit
import SwiftUI
import Testing
import WebKit
@testable import Folium

/// The real click-through path for issue #19's remote-content opt-in, split
/// out from `RemoteContentOptInTests.swift` (which was already at the
/// file-length limit) — the two files together are what full seam coverage
/// for the feature means.
///
/// Every test in `RemoteContentOptInTests` drives `MarkdownWebView
/// .Coordinator` directly, standing in for what `updateNSView` does on a
/// reload. This one drives the actual production path instead: a real
/// `RemoteContentState.allow()` call, a real SwiftUI re-render of a real
/// `MarkdownWebView`, and the real `updateNSView` this app runs when a user
/// clicks "Load" — the one seam `MarkdownWebView.swift` and `FoliumApp.swift`
/// (both coverage-excluded host glue) own that nothing in
/// `RemoteContentOptInTests` reaches. `DocumentView` itself is file-private
/// to `FoliumApp.swift`, so `OptInHarness` below mirrors its wiring instead
/// of being able to use it directly.
@MainActor
@Suite(.serialized)
struct RemoteContentTransitionTests {
    init() {
        AppKitHost.startIfNeeded()
    }

    @Test func loadTogglingRemoteContentAllowedReloadsTheShellAndKeepsTheBodyRendered() async throws {
        let bodyHTML = #"<p>hello from the document</p><img id="remote-img" src="https://example.invalid/badge.png">"#
        let state = RemoteContentState(bodyHTML: bodyHTML)
        let window = hostedOptInHarness(state: state, bodyHTML: bodyHTML)
        defer { window.close() }
        let contentView = try #require(window.contentView)
        let webView = try #require(findWebView(in: contentView))

        #expect(await waitUntil(pumping: window) { !webView.isLoading })
        #expect(webView.url?.lastPathComponent == "page.html")
        let initialText = try await webView.evaluateJavaScript(
            "document.getElementById('markdown-content').textContent"
        )
        #expect((initialText as? String)?.contains("hello from the document") == true)

        // The click: RemoteContentState.allow() is exactly what a tap on
        // FoliumApp.swift's "Load" button calls.
        state.allow()

        #expect(await waitUntil(pumping: window) { webView.url?.lastPathComponent == "page-remote.html" })
        #expect(await waitUntil(pumping: window) { !webView.isLoading })

        // The point of this test: the reload's queued body still lands.
        // `MarkdownWebViewState.beginReload()`/`shellDidFinishLoading()` are
        // unit-tested in isolation, but only this proves the real
        // `Coordinator.webView(_:didFinish:)` callback actually reaches them
        // through a real reload.
        let textAfterReload = try await webView.evaluateJavaScript(
            "document.getElementById('markdown-content').textContent"
        )
        #expect((textAfterReload as? String)?.contains("hello from the document") == true)
    }

    // MARK: - Helpers

    /// Builds a real window around `OptInHarness`, laid out so
    /// `MarkdownWebView.makeNSView` has actually run — the same pattern
    /// `PreferencesTests.hosting` uses for its own `NSViewRepresentable`s.
    private func hostedOptInHarness(state: RemoteContentState, bodyHTML: String) -> NSWindow {
        let hostingView = NSHostingView(rootView: OptInHarness(state: state, bodyHTML: bodyHTML))
        hostingView.frame = NSRect(x: 0, y: 0, width: 1012, height: 800)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        // A programmatically created NSWindow releases itself on close, which
        // double-frees once ARC also lets go — a segfault that takes the
        // whole bundle down instead of failing a test (same fix as
        // ScrollKeyTests / ContentSecurityPolicyTests).
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        hostingView.layoutSubtreeIfNeeded()
        return window
    }

    /// Walks the view tree `NSHostingView` builds to find the `WKWebView`
    /// (actually a `ScrollKeyWebView`) `MarkdownWebView.makeNSView` created,
    /// since nothing hands a test that view directly when SwiftUI is what
    /// constructs it.
    private func findWebView(in view: NSView) -> WKWebView? {
        if let webView = view as? WKWebView { return webView }
        for subview in view.subviews {
            if let found = findWebView(in: subview) { return found }
        }
        return nil
    }

    /// Polls `condition`, forcing `window`'s view tree to process any
    /// pending SwiftUI view-graph update on every check. Nothing exposed to
    /// a test observes "SwiftUI ran `updateNSView` after this `@Published`
    /// change" directly — the same reason `ContentSecurityPolicyTests
    /// .waitUntil` polls for a smooth scroll's progress instead of waiting
    /// on a callback.
    private func waitUntil(
        pumping window: NSWindow,
        within timeout: Duration = .seconds(5),
        _ condition: () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            window.contentView?.layoutSubtreeIfNeeded()
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        window.contentView?.layoutSubtreeIfNeeded()
        return condition()
    }
}

/// Mirrors `FoliumApp.swift`'s private `DocumentView` wiring — a
/// `MarkdownWebView` whose `remoteContentAllowed` follows a
/// `RemoteContentState` — since `DocumentView` itself is file-private to
/// `FoliumApp.swift` and unreachable from a test.
private struct OptInHarness: View {
    @ObservedObject var state: RemoteContentState
    let bodyHTML: String

    var body: some View {
        MarkdownWebView(bodyHTML: bodyHTML, scrollKeys: .standard, remoteContentAllowed: state.isAllowed)
    }
}

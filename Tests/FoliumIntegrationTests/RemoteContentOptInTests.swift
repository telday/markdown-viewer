import AppKit
import Testing
import WebKit
@testable import Folium

/// Seam tests for issue #19: the per-document "Load remote images" opt-in
/// that reloads `MarkdownWebView`'s shell from `page.html` (strict) to
/// `page-remote.html` (also admits `https:` for images and media).
///
/// Follows `ContentSecurityPolicyTests`' pattern throughout — same
/// `securitypolicyviolation`-event assertion, same reasoning for why. `CSP`
/// tests fire pre-request, so `example.invalid` (an IANA-reserved domain
/// guaranteed never to resolve) is deterministic with no live network: what
/// is being asserted is whether CSP objected before any request went out,
/// not whether the request succeeded. A remote-URL test that instead waited
/// on the request's outcome would prove nothing in a CI sandbox with no
/// network either way — the resource fails to load whether CSP blocked it
/// or the network simply isn't there.
@MainActor
@Suite(.serialized)
struct RemoteContentOptInTests {
    init() {
        AppKitHost.startIfNeeded()
    }

    // MARK: - Blocked by default (the strict shell, unchanged from #17)

    @Test func remoteImageIsBlockedByDefaultUnderTheStrictShell() async throws {
        let (webView, waiter) = try await loadedWebView(
            shellURL: MarkdownPage.strictPageURL,
            remoteContentAllowed: false
        )
        defer { webView.window?.close() }
        _ = waiter // kept alive: `navigationDelegate` is a weak reference

        let violation = try await recordFirstCSPViolation(
            on: webView,
            injectingIntoMarkdownContent: #"<img id="remote-img" src="https://example.invalid/leak.png">"#
        )

        let recorded = try #require(
            violation,
            "no securitypolicyviolation fired for a remote <img> under the strict shell"
        )
        #expect(recorded["directive"] as? String == "img-src")
        #expect((recorded["blockedURI"] as? String)?.contains("example.invalid") == true)
    }

    // MARK: - The opt-in actually permits the load

    @Test func remoteImageRecordsNoViolationUnderTheOptInShell() async throws {
        let (webView, waiter) = try await loadedWebView(
            shellURL: MarkdownPage.remotePageURL,
            remoteContentAllowed: true
        )
        defer { webView.window?.close() }
        _ = waiter // kept alive: `navigationDelegate` is a weak reference

        let violation = try await recordFirstCSPViolation(
            on: webView,
            injectingIntoMarkdownContent: #"<img id="remote-img" src="https://example.invalid/leak.png">"#
        )

        // This is the assertion that survives having no network in CI: not
        // that the image rendered (it can't — example.invalid never
        // resolves anywhere), but that CSP itself raised no img-src
        // objection to attempting the request.
        #expect(violation == nil)
    }

    // MARK: - http: stays blocked even after opt-in (issue #19's decision)

    @Test func httpRemoteImageIsStillBlockedUnderTheOptInShell() async throws {
        let (webView, waiter) = try await loadedWebView(
            shellURL: MarkdownPage.remotePageURL,
            remoteContentAllowed: true
        )
        defer { webView.window?.close() }
        _ = waiter // kept alive: `navigationDelegate` is a weak reference

        let violation = try await recordFirstCSPViolation(
            on: webView,
            injectingIntoMarkdownContent: #"<img id="remote-img" src="http://example.invalid/leak.png">"#
        )

        let recorded = try #require(violation, "http: must stay blocked after opt-in — only https: is ever unblocked")
        #expect(recorded["directive"] as? String == "img-src")
    }

    // MARK: - media-src (video), not just img-src — issue #19 relaxes both

    @Test func remoteVideoIsBlockedByDefaultUnderTheStrictShell() async throws {
        let (webView, waiter) = try await loadedWebView(
            shellURL: MarkdownPage.strictPageURL,
            remoteContentAllowed: false
        )
        defer { webView.window?.close() }
        _ = waiter // kept alive: `navigationDelegate` is a weak reference

        let violation = try await recordFirstCSPViolation(
            on: webView,
            injectingIntoMarkdownContent: #"<video id="remote-video" src="https://example.invalid/movie.mp4"></video>"#
        )

        let recorded = try #require(
            violation,
            "no securitypolicyviolation fired for a remote <video src> under the strict shell"
        )
        // WebKit reports an element's own media fetch under the more
        // specific "media-src-elem" sub-directive, the same pattern
        // ContentSecurityPolicyTests sees for a <link rel="stylesheet"> and
        // "style-src-elem".
        #expect((recorded["directive"] as? String)?.hasPrefix("media-src") == true)
        #expect((recorded["blockedURI"] as? String)?.contains("example.invalid") == true)
    }

    @Test func remoteVideoRecordsNoViolationUnderTheOptInShell() async throws {
        let (webView, waiter) = try await loadedWebView(
            shellURL: MarkdownPage.remotePageURL,
            remoteContentAllowed: true
        )
        defer { webView.window?.close() }
        _ = waiter // kept alive: `navigationDelegate` is a weak reference

        let violation = try await recordFirstCSPViolation(
            on: webView,
            injectingIntoMarkdownContent: #"<video id="remote-video" src="https://example.invalid/movie.mp4"></video>"#
        )

        // `media-src` is asserted against the raw CSP string in
        // MarkdownPageTests, but nothing before this exercised it in a real
        // WKWebView: the img-src tests above don't touch it, and a `poster`
        // attribute — the other thing `RemoteContent` scans — is fetched
        // under `img-src` per the CSP spec, not `media-src`. Only an actual
        // `<video src>` proves this directive specifically was relaxed.
        #expect(violation == nil)
    }

    // MARK: - Positive control: local file: images still load, under both shells

    @Test func localFileImageStillLoadsUnderTheStrictShell() async throws {
        try await assertLocalFileImageLoads(shellFileName: "page.html")
    }

    @Test func localFileImageStillLoadsUnderTheOptInShell() async throws {
        // Without this, a page-remote.html typo broad enough to also break
        // img-src's file: token (e.g. "img-src https:", dropping file:
        // entirely) would still pass the two tests above while silently
        // breaking every local image a document embeds — a floor-1
        // violation, not just a network one.
        try await assertLocalFileImageLoads(shellFileName: "page-remote.html")
    }

    // MARK: - Helpers

    /// A 1x1 transparent PNG — the smallest file that is unambiguously a
    /// real, loadable image rather than a stand-in. Mirrors
    /// `ContentSecurityPolicyTests.onePixelPNG`.
    private static let onePixelPNG = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!

    /// Loads a throwaway copy of `shellFileName` (the real shell from the
    /// bundle, not a hand-written fixture) alongside a local PNG, and
    /// asserts the PNG renders. A temp directory, rather than
    /// `MarkdownPage.resourceBaseURL` directly: writing a fixture file into
    /// that tree would mutate the same build output `make verify-bundle`
    /// inspects.
    private func assertLocalFileImageLoads(shellFileName: String) async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let sourceURL = MarkdownPage.resourceBaseURL.appendingPathComponent("Resources/\(shellFileName)")
        let shellHTML = try String(contentsOf: sourceURL, encoding: .utf8)
        try shellHTML.write(to: tempRoot.appendingPathComponent(shellFileName), atomically: true, encoding: .utf8)
        try Self.onePixelPNG.write(to: tempRoot.appendingPathComponent("local.png"))

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        let waiter = NavigationWaiter()
        webView.navigationDelegate = waiter
        webView.loadFileURL(tempRoot.appendingPathComponent(shellFileName), allowingReadAccessTo: tempRoot)
        await waiter.waitUntilFinished()

        let functionBody = """
        return new Promise(function (resolve) {
          var img = document.createElement('img');
          img.onload = function () { resolve(img.naturalWidth); };
          img.onerror = function () { resolve(-1); };
          img.src = 'local.png';
          document.body.appendChild(img);
          setTimeout(function () { resolve(-2); }, 2000);
        });
        """
        let width = try await webView.callAsyncJavaScript(functionBody, in: nil, contentWorld: .page)
        #expect((width as? Int ?? -1) > 0, "local image failed to load under \(shellFileName)")
    }

    /// Loads `shellURL` (the real shell from the bundle) with a real
    /// `MarkdownWebView.Coordinator` as its navigation delegate, attached to
    /// a real, key `NSWindow` — the same setup
    /// `ContentSecurityPolicyTests.loadedWebView` uses, generalized over
    /// which shell file and opt-in state to load. `remoteContentAllowed`
    /// must match `shellURL`: it's what `Coordinator.decidePolicyFor` uses
    /// to compute which file counts as "the shell navigating to itself"
    /// rather than a navigation to police.
    private func loadedWebView(
        shellURL: URL,
        remoteContentAllowed: Bool
    ) async throws -> (webView: WKWebView, waiter: CoordinatorWaiter) {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1012, height: 800))
        let coordinator = MarkdownWebView.Coordinator(openExternal: { _ in })
        coordinator.remoteContentAllowed = remoteContentAllowed
        let waiter = CoordinatorWaiter(coordinator: coordinator)
        webView.navigationDelegate = waiter
        webView.loadFileURL(shellURL, allowingReadAccessTo: MarkdownPage.resourceBaseURL)
        await waiter.waitUntilFinished()

        let window = NSWindow(
            contentRect: webView.frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        // A programmatically created NSWindow releases itself on close, which
        // double-frees once ARC also lets go — a segfault that takes the
        // whole bundle down instead of failing a test (same fix as
        // ScrollKeyTests / ContentSecurityPolicyTests).
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.makeKeyAndOrderFront(nil)
        return (webView, waiter)
    }

    /// Attaches a `securitypolicyviolation` listener, then injects `html`
    /// into `#markdown-content` via `innerHTML`, and returns the first
    /// recorded violation's `directive`/`blockedURI`, or `nil` if none
    /// fired. Mirrors `ContentSecurityPolicyTests.recordFirstCSPViolation` —
    /// see its doc comment for why `innerHTML` rather than
    /// `document.createElement` is what makes the event actually fire.
    private func recordFirstCSPViolation(
        on webView: WKWebView,
        injectingIntoMarkdownContent html: String
    ) async throws -> [String: Any]? {
        let htmlJSON = try JSONEncoder().encode(html)
        let htmlJSString = String(data: htmlJSON, encoding: .utf8)!
        let functionBody = """
        return new Promise(function (resolve) {
          document.addEventListener('securitypolicyviolation', function handler(e) {
            document.removeEventListener('securitypolicyviolation', handler);
            resolve({ directive: e.violatedDirective, blockedURI: e.blockedURI });
          });
          document.getElementById('markdown-content').innerHTML = \(htmlJSString);
          setTimeout(function () { resolve(null); }, 2000);
        });
        """
        let result = try await webView.callAsyncJavaScript(functionBody, in: nil, contentWorld: .page)
        return result as? [String: Any]
    }
}

/// Bridges `WKNavigationDelegate`'s completion callback to `async/await`,
/// with no `decidePolicyFor` override. Mirrors
/// `ContentSecurityPolicyTests.NavigationWaiter` — needed again here
/// because that one is file-private, and this file loads a temp-directory
/// copy of the shell, which the real `Coordinator`'s `decidePolicyFor`
/// (comparing against `MarkdownPage.strictPageURL`/`remotePageURL` specifically)
/// would reject every navigation into, including the page's own initial
/// load.
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

/// Forwards to a real `MarkdownWebView.Coordinator` while also resolving a
/// continuation on `didFinish`. Mirrors
/// `ContentSecurityPolicyTests.CoordinatorWaiter`, duplicated for the same
/// file-privacy reason as `NavigationWaiter` above.
@MainActor
private final class CoordinatorWaiter: NSObject, WKNavigationDelegate {
    private let coordinator: MarkdownWebView.Coordinator
    private var continuation: CheckedContinuation<Void, Never>?
    private var finished = false

    init(coordinator: MarkdownWebView.Coordinator) {
        self.coordinator = coordinator
    }

    func waitUntilFinished() async {
        if finished { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        coordinator.webView(webView, didFinish: navigation)
        finished = true
        continuation?.resume()
        continuation = nil
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        coordinator.webView(webView, decidePolicyFor: navigationAction, decisionHandler: decisionHandler)
    }
}

import AppKit
import Testing
import WebKit
@testable import Folium

/// Seam tests for issue #17: `CONTEXT.md`'s no-network floor, enforced by the
/// CSP `<meta>` tag in `Resources/page.html` and by
/// `MarkdownWebView.Coordinator.decidePolicyFor`.
///
/// The remote tests assert on the browser's own `securitypolicyviolation`
/// event, which fires pre-request — before any network attempt — rather
/// than on whether the resource loaded. That means the target URL doesn't
/// need to be reachable at all, which is what makes these deterministic
/// without a live network or a test-hosted server: `example.invalid` is an
/// IANA-reserved domain guaranteed never to resolve. The event only fires
/// reliably here via `element.innerHTML = ...` (the same DOM-injection path
/// `window.FoliumRenderBody` uses in production) — `document.createElement`
/// + `appendChild`, tried first, never saw it fire.
///
/// Runs in a real `WKWebView` (and, for the two navigation tests, a real
/// `NSWindow` — smooth-scroll animation and `decidePolicyFor` link clicks
/// were only observed to behave like the real app once attached to one, the
/// same reason `ScrollKeyTests` does it), so this lives in the integration
/// target rather than the unit/logic layer.
@MainActor
@Suite(.serialized)
struct ContentSecurityPolicyTests {
    init() {
        AppKitHost.startIfNeeded()
    }

    // MARK: - img-src / style-src

    /// Positive control: without this, a CSP broad enough to block every
    /// fetch directive (or a typo'd `default-src 'none'` with no `img-src`
    /// override — verified fact #4 in the spec: that also blocks local
    /// images) would pass the remote-blocked tests below and silently break
    /// every local image a document embeds — a floor-1 ("the document says
    /// what the file says") violation, not just a network one.
    ///
    /// Loads a throwaway copy of the shell rather than the real
    /// `MarkdownPage.resourceBaseURL` tree `loadedWebView` uses: writing a
    /// fixture file into that directory would mutate the same build output
    /// `make verify-bundle` inspects.
    @Test func localFileImageLoadsUnderCSP() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let shellHTML = try String(contentsOf: MarkdownPage.strictPageURL, encoding: .utf8)
        try shellHTML.write(to: tempRoot.appendingPathComponent("page.html"), atomically: true, encoding: .utf8)
        try Self.onePixelPNG.write(to: tempRoot.appendingPathComponent("local.png"))

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        let waiter = NavigationWaiter()
        webView.navigationDelegate = waiter
        webView.loadFileURL(tempRoot.appendingPathComponent("page.html"), allowingReadAccessTo: tempRoot)
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
        #expect((width as? Int ?? -1) > 0)
    }

    /// The actual no-network-floor assertion for images: a remote `<img>`
    /// never loads, and `securitypolicyviolation` confirms CSP refused it
    /// rather than some unrelated failure.
    @Test func remoteImageIsBlockedByCSPAndReportsAViolation() async throws {
        let (webView, waiter) = try await loadedWebView(recorder: OpenedURLRecorder())
        defer { webView.window?.close() }
        _ = waiter // kept alive: `navigationDelegate` is a weak reference

        let violation = try await recordFirstCSPViolation(
            on: webView,
            injectingIntoMarkdownContent: #"<img id="remote-img" src="https://example.invalid/leak.png">"#
        )
        let widthResult = try await webView.evaluateJavaScript("document.getElementById('remote-img').naturalWidth")
        #expect(widthResult as? Int == 0)

        let recorded = try #require(violation, "no securitypolicyviolation event fired for the remote <img>")
        #expect(recorded["directive"] as? String == "img-src")
        #expect((recorded["blockedURI"] as? String)?.contains("example.invalid") == true)
    }

    /// The same no-network-floor assertion, for the other resource kind a
    /// document could pull in remotely: a `<link rel="stylesheet">`.
    /// Uncovered before this test — the img-src tests above don't exercise
    /// `style-src` at all, and a document could reference a remote
    /// stylesheet the same way it references a remote image.
    @Test func remoteStylesheetIsBlockedByCSPAndReportsAViolation() async throws {
        let (webView, waiter) = try await loadedWebView(recorder: OpenedURLRecorder())
        defer { webView.window?.close() }
        _ = waiter // kept alive: `navigationDelegate` is a weak reference

        let linkTag = #"<link id="remote-css" rel="stylesheet" href="https://example.invalid/leak.css">"#
        let violation = try await recordFirstCSPViolation(on: webView, injectingIntoMarkdownContent: linkTag)
        let sheetResult = try await webView.evaluateJavaScript("!!document.getElementById('remote-css').sheet")
        #expect(sheetResult as? Bool == false)

        let recorded = try #require(violation, "no securitypolicyviolation event fired for the remote stylesheet")
        // WebKit reports link-element style loads under the more specific
        // "style-src-elem" sub-directive rather than plain "style-src".
        #expect((recorded["directive"] as? String)?.hasPrefix("style-src") == true)
        #expect((recorded["blockedURI"] as? String)?.contains("example.invalid") == true)
    }

    // MARK: - script-src-attr

    @Test func inlineEventHandlerAttributeDoesNotFire() async throws {
        let (webView, waiter) = try await loadedWebView(recorder: OpenedURLRecorder())
        defer { webView.window?.close() }
        _ = waiter // kept alive: `navigationDelegate` is a weak reference

        // Verified without CSP: this handler runs and window.PWNED becomes
        // true. script-src 'self' blocks inline handlers as a
        // "script-src-attr" violation, so it must stay undefined.
        let functionBody = """
        return new Promise(function (resolve) {
          var img = document.createElement('img');
          img.setAttribute('src', 'this-file-does-not-exist.png');
          img.setAttribute('onerror', 'window.PWNED = true');
          document.body.appendChild(img);
          setTimeout(function () { resolve(window.PWNED === true); }, 500);
        });
        """
        let pwned = try await webView.callAsyncJavaScript(functionBody, in: nil, contentWorld: .page)
        #expect(pwned as? Bool == false)
    }

    // MARK: - Navigation policy

    @Test func externalLinkDoesNotNavigateAndOpensThroughTheInjectedOpener() async throws {
        let recorder = OpenedURLRecorder()
        let (webView, waiter) = try await loadedWebView(recorder: recorder)
        defer { webView.window?.close() }
        _ = waiter // kept alive: `navigationDelegate` is a weak reference

        // Wrapped in a no-return IIFE: the last statement's value otherwise
        // becomes the script's result, and appendChild returns the appended
        // Node — a type evaluateJavaScript can't bridge back to Swift.
        _ = try await webView.evaluateJavaScript("""
        (function () {
          var a = document.createElement('a');
          a.id = 'external-link';
          a.href = 'https://example.com/page';
          a.textContent = 'external';
          document.body.appendChild(a);
        })();
        """)
        _ = try await webView.evaluateJavaScript("document.getElementById('external-link').click();")

        #expect(await waitUntil { recorder.openedURLs.count == 1 })
        #expect(recorder.openedURLs == [URL(string: "https://example.com/page")!])
        // The click cancelled navigation, so the web view never left the shell.
        #expect(webView.url?.path == MarkdownPage.strictPageURL.path)
    }

    @Test func inDocumentAnchorLinkScrollsInsteadOfNavigating() async throws {
        let (webView, waiter) = try await loadedWebView(recorder: OpenedURLRecorder())
        defer { webView.window?.close() }
        _ = waiter // kept alive: `navigationDelegate` is a weak reference

        _ = try await webView.evaluateJavaScript("""
        (function () {
          var link = document.createElement('a');
          link.id = 'anchor-link';
          link.href = '#usage';
          link.textContent = 'go to usage';
          document.body.appendChild(link);
          var spacer = document.createElement('div');
          spacer.style.height = '4000px';
          document.body.appendChild(spacer);
          var target = document.createElement('div');
          target.id = 'usage';
          target.textContent = 'usage section';
          document.body.appendChild(target);
        })();
        """)
        _ = try await webView.evaluateJavaScript("document.getElementById('anchor-link').click();")

        #expect(await waitUntil { try await self.scrollY(of: webView) > 0 })
        // The click cancelled navigation the same way the external link did;
        // scrolling happens through evaluateJavaScript, not a URL change.
        // Checking `.path` alone would not have teeth here: WebKit's own
        // *default* handling of an in-page `#usage` link (i.e. what happens
        // if `decidePolicyFor` is never called) also scrolls to the target
        // and leaves `.path` unchanged — the fragment is what it adds, so
        // that's what a regression back to default handling would show up
        // in. `MarkdownWebView.Coordinator` cancels the navigation before it
        // ever reaches the URL bar, so the fragment must never appear.
        #expect(webView.url?.path == MarkdownPage.strictPageURL.path)
        #expect(webView.url?.fragment == nil)
    }

    // MARK: - Helpers

    /// A 1x1 transparent PNG — the smallest file that is unambiguously a
    /// real, loadable image rather than a stand-in.
    private static let onePixelPNG = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!

    /// Loads the real shell — the same `loadFileURL` call `MarkdownWebView`
    /// makes — with a real `MarkdownWebView.Coordinator` as its navigation
    /// delegate so `decidePolicyFor` runs, and attaches it to a real,
    /// key `NSWindow`. `ScrollKeyTests` found this necessary for a smooth
    /// scroll to actually progress; the same shell/coordinator setup is
    /// reused for the non-scrolling tests above for consistency.
    private func loadedWebView(
        recorder: OpenedURLRecorder
    ) async throws -> (webView: WKWebView, waiter: CoordinatorWaiter) {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1012, height: 800))
        let coordinator = MarkdownWebView.Coordinator(openExternal: { url in recorder.record(url) })
        let waiter = CoordinatorWaiter(coordinator: coordinator)
        webView.navigationDelegate = waiter
        webView.loadFileURL(MarkdownPage.strictPageURL, allowingReadAccessTo: MarkdownPage.resourceBaseURL)
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
        // ScrollKeyTests).
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.makeKeyAndOrderFront(nil)
        return (webView, waiter)
    }

    /// Attaches a `securitypolicyviolation` listener, then injects `html`
    /// into `#markdown-content` via `innerHTML` (see the type doc comment
    /// for why `innerHTML`, not `createElement`), and returns the first
    /// recorded violation's `directive`/`blockedURI`, or `nil` if none
    /// fired. One evaluateJavaScript call, listener before content, so
    /// there's no window where a violation could fire unobserved.
    private func recordFirstCSPViolation(
        on webView: WKWebView,
        injectingIntoMarkdownContent html: String
    ) async throws -> [String: Any]? {
        // JSON-encoded, the same way MarkdownPage.renderBodyScript encodes
        // rendered document HTML, since this string also contains quotes
        // (the injected tag's own href/src attributes) that would otherwise
        // break out of the JS string literal below.
        let htmlJSON = try JSONEncoder().encode(html)
        let htmlJSString = String(data: htmlJSON, encoding: .utf8)!
        let functionBody = """
        return new Promise(function (resolve) {
          document.addEventListener('securitypolicyviolation', function handler(e) {
            document.removeEventListener('securitypolicyviolation', handler);
            resolve({ directive: e.violatedDirective, blockedURI: e.blockedURI });
          });
          document.getElementById('markdown-content').innerHTML = \(htmlJSString);
          // The violation fires pre-request, synchronously with CSP in
          // force; this is only a ceiling for the case something regresses.
          setTimeout(function () { resolve(null); }, 2000);
        });
        """
        let result = try await webView.callAsyncJavaScript(functionBody, in: nil, contentWorld: .page)
        return result as? [String: Any]
    }

    private func scrollY(of webView: WKWebView) async throws -> Double {
        let result = try await webView.evaluateJavaScript("window.scrollY")
        return (result as? Double) ?? 0
    }

    /// Polls rather than sleeping a fixed duration: a smooth scroll is an
    /// animation, and how long a click takes to reach `decidePolicyFor` is
    /// not something a test should hardcode a duration for.
    private func waitUntil(
        within timeout: Duration = .seconds(5),
        _ condition: () async throws -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if (try? await condition()) == true { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return (try? await condition()) == true
    }
}

/// Bridges `WKNavigationDelegate`'s completion callback to `async/await`,
/// with no `decidePolicyFor` override — used only where a test needs a page
/// to finish loading and has no interest in navigation policy. (Reusing
/// `CoordinatorWaiter` for that would run the real `Coordinator`, whose
/// `decidePolicyFor` compares against `MarkdownPage.strictPageURL` specifically —
/// wrong shell URL for a temp-directory copy of the page, and every
/// navigation, including the page's own initial load, would come back
/// `.block`.)
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

/// Records what would have been opened externally, standing in for
/// `NSWorkspace.shared.open(_:)` — see the `openExternal` doc comment on
/// `MarkdownWebView.Coordinator` for why the production default is injected
/// rather than called directly here.
@MainActor
private final class OpenedURLRecorder {
    private(set) var openedURLs: [URL] = []
    func record(_ url: URL) { openedURLs.append(url) }
}

/// Forwards to a real `MarkdownWebView.Coordinator` — the actual production
/// navigation delegate under test — while also resolving a continuation on
/// `didFinish`, since `Coordinator` itself exposes no way to wait for the
/// shell to finish loading.
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

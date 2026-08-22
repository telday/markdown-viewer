import AppKit
import Testing
import WebKit
@testable import Folium

/// Seam tests for issue #17: `CONTEXT.md`'s no-network floor, enforced by the
/// CSP `<meta>` tag in `Resources/page.html` and by
/// `MarkdownWebView.Coordinator.decidePolicyFor`.
///
/// The remote-image test points at a real `http://127.0.0.1` server the test
/// spins up itself (`LocalHTTPServer`, below), rather than either a live
/// internet host or a made-up unreachable one. Both of those were tried
/// first and rejected: a live host makes the assertion's truth depend on
/// whatever network access happens to exist wherever the suite runs (CI is
/// expected to have none, so a remote fetch would fail identically whether
/// or not CSP exists — no teeth either way), and reusing that reasoning to
/// swap in a *local* fixture file instead of testing the remote case at all
/// turned out to be wrong in a different way: it silently changed the
/// shipped policy from `img-src 'self'` to `'none'`, which blocks local
/// images too and would have broken every `![](photo.png)` in every
/// document. A loopback HTTP server sidesteps both problems — it is
/// reachable with zero external network, and it is genuinely remote from
/// the CSP's point of view (a different origin from the `file://` shell),
/// so `img-src 'self'` must still refuse it.
///
/// Listens for the browser's own `securitypolicyviolation` event (confirmed
/// to fire reliably here, via `document.getElementById(...).innerHTML = ...`
/// — the same DOM-injection path `window.FoliumRenderBody` uses in
/// production, rather than `document.createElement`/`appendChild`, which is
/// what an earlier version of this test used and never saw the event fire).
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

    // MARK: - img-src

    /// Positive control: without this, a CSP broad enough to block `img-src`
    /// entirely (or a typo'd `default-src 'none'` with no `img-src` override
    /// — verified fact #4 in the spec: that also blocks local images) would
    /// pass the remote-blocked test below and silently break every local
    /// image a document embeds — a floor-1 ("the document says what the file
    /// says") violation, not just a network one.
    @Test func localFileImageLoadsUnderCSP() async throws {
        let (webView, waiter) = try await loadedWebView(recorder: OpenedURLRecorder())
        defer { webView.window?.close() }
        _ = waiter

        let fixtureName = "csp-fixture-\(UUID().uuidString).png"
        let fixtureURL = MarkdownPage.resourceBaseURL
            .appendingPathComponent("Resources")
            .appendingPathComponent(fixtureName)
        try Self.onePixelPNG.write(to: fixtureURL)
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let functionBody = """
        return new Promise(function (resolve) {
          var img = document.createElement('img');
          img.onload = function () { resolve(img.naturalWidth); };
          img.onerror = function () { resolve(-1); };
          img.src = '\(fixtureName)';
          document.body.appendChild(img);
          setTimeout(function () { resolve(-2); }, 2000);
        });
        """
        let width = try await webView.callAsyncJavaScript(functionBody, in: nil, contentWorld: .page)
        #expect((width as? Int ?? -1) > 0)
    }

    /// The actual no-network-floor assertion: a remote `<img>` never loads,
    /// and the browser's own `securitypolicyviolation` event confirms *why*
    /// — CSP refused it pre-request, not some other, unrelated failure. See
    /// the type doc comment for why this points at a loopback server this
    /// test starts itself, and why the DOM content goes in via `innerHTML`.
    @Test func remoteImageIsBlockedByCSPAndReportsAViolation() async throws {
        let server = try LocalHTTPServer(fileData: Self.onePixelPNG, fileName: "remote.png")
        defer { server.stop() }
        try await server.waitUntilReady()

        let (webView, waiter) = try await loadedWebView(recorder: OpenedURLRecorder())
        defer { webView.window?.close() }
        _ = waiter

        // Listener attached in the same script, before the img is inserted,
        // so there's no window where the violation could fire unobserved.
        _ = try await webView.evaluateJavaScript("""
        (function () {
          window.__cspViolations = [];
          document.addEventListener('securitypolicyviolation', function (e) {
            window.__cspViolations.push({ directive: e.violatedDirective, blockedURI: e.blockedURI });
          });
          document.getElementById('markdown-content').innerHTML =
            '<img id="remote-img" src="http://127.0.0.1:\(server.port)/remote.png">';
        })();
        """)
        // The violation fires synchronously with CSP in force; this is only
        // a ceiling for the case something regresses, not an expected wait.
        try await Task.sleep(nanoseconds: 1_500_000_000)

        let widthResult = try await webView.evaluateJavaScript("document.getElementById('remote-img').naturalWidth")
        #expect(widthResult as? Int == 0)

        let violationsResult = try await webView.evaluateJavaScript("window.__cspViolations")
        let violations = try #require(violationsResult as? [[String: Any]])
        let violation = try #require(violations.first, "no securitypolicyviolation event fired for the remote <img>")
        #expect(violation["directive"] as? String == "img-src")
        #expect((violation["blockedURI"] as? String)?.contains("127.0.0.1") == true)
    }

    // MARK: - script-src-attr

    @Test func inlineEventHandlerAttributeDoesNotFire() async throws {
        let (webView, waiter) = try await loadedWebView(recorder: OpenedURLRecorder())
        defer { webView.window?.close() }
        _ = waiter

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
        _ = waiter

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
        #expect(webView.url?.path == MarkdownPage.pageURL.path)
    }

    @Test func inDocumentAnchorLinkScrollsInsteadOfNavigating() async throws {
        let (webView, waiter) = try await loadedWebView(recorder: OpenedURLRecorder())
        defer { webView.window?.close() }
        _ = waiter

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
        #expect(webView.url?.path == MarkdownPage.pageURL.path)
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
        webView.loadFileURL(MarkdownPage.pageURL, allowingReadAccessTo: MarkdownPage.resourceBaseURL)
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

/// A real, minimal HTTP server on `127.0.0.1`, so the remote-image test has
/// a genuinely different-origin URL to point at without depending on
/// internet access existing wherever the suite runs.
///
/// Backed by `python3 -m http.server` as a subprocess rather than
/// `Network.framework`'s `NWListener`: `NWListener` fails immediately with
/// `POSIXErrorCode(rawValue: 22)` ("Invalid argument") in this sandbox, for
/// a bare `swift` script as much as inside `swift test` — nothing to do with
/// this test target specifically. `python3` is already a build-time
/// dependency of this repo (`scripts/vendor-highlightjs.sh`'s `npm`
/// tooling notwithstanding, `python3` ships with Xcode's command line
/// tools), so this doesn't add a new one.
final class LocalHTTPServer {
    let port: Int
    private let process: Process
    private let directory: URL

    init(fileData: Data, fileName: String) throws {
        port = Int.random(in: 20000..<40000)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileData.write(to: directory.appendingPathComponent(fileName))

        process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-m", "http.server", String(port), "--bind", "127.0.0.1", "--directory", directory.path]
        // Swallowed rather than left connected to the test runner's own
        // stdout/stderr: http.server logs one line per request, which would
        // otherwise interleave with `swift test`'s own output.
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    /// Polls the server with a real request rather than a fixed sleep,
    /// since `python3 -m http.server`'s startup time isn't specified.
    func waitUntilReady() async throws {
        let url = URL(string: "http://127.0.0.1:\(port)/")!
        for _ in 0..<50 {
            if let (_, response) = try? await URLSession.shared.data(from: url),
               (response as? HTTPURLResponse) != nil {
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    func stop() {
        process.terminate()
        try? FileManager.default.removeItem(at: directory)
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

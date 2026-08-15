import AppKit
import Combine
import Foundation
import Testing
import WebKit
@testable import Folium

/// End-to-end live-reload (issue #7): a real file on disk, a real
/// `DispatchSource` watch, the real coalescing window on the real clock, and a
/// real `WKWebView` showing the result.
///
/// The unit tests drive each piece with the timing held still. What only this
/// tier can show is that the pieces are actually connected — that editing the
/// file in another app changes the pixels, with nothing asked of the user. It
/// also stands in for the `DocumentView` glue inside the coverage-excluded
/// `FoliumApp.swift`, which does nothing but hold one `LiveDocument` and hand
/// its body HTML to `MarkdownWebView`.
@MainActor
struct LiveReloadTests {
    @Test func anExternalEditRepaintsTheDocumentWithNothingAskedOfTheUser() async throws {
        let file = try TempFile(contents: "# Before")
        let document = LiveDocument(text: "# Before", fileURL: file.url)
        let webView = try await loadedWebView(showing: document.bodyHTML)
        #expect(try await heading(of: webView) == "Before")

        // The whole feature, in one line: somebody else writes the file.
        try file.write("# After")

        #expect(await waitUntil { document.bodyHTML.contains("<h1>After</h1>") })
        try await inject(document.bodyHTML, into: webView)
        #expect(try await heading(of: webView) == "After")
    }

    @Test func anAtomicSaveRepaints_andTheWatchSurvivesToDoItAgain() async throws {
        // The way most editors save. Getting this wrong gives a document that
        // live-reloads exactly once and then quietly stops — which is why the
        // second save is asserted, not just the first.
        let file = try TempFile(contents: "# One")
        let document = LiveDocument(text: "# One", fileURL: file.url)

        try file.atomicallyReplace(with: "# Two")
        #expect(await waitUntil { document.bodyHTML.contains("<h1>Two</h1>") })

        try file.atomicallyReplace(with: "# Three")
        #expect(await waitUntil { document.bodyHTML.contains("<h1>Three</h1>") })

        let webView = try await loadedWebView(showing: document.bodyHTML)
        #expect(try await heading(of: webView) == "Three")
    }

    @Test func aBurstOfWritesRepaintsOnceRatherThanOncePerWrite() async throws {
        // An editor's autosave, or a formatter running on save. Every write
        // here is a separate reload's worth of file-system events.
        let file = try TempFile(contents: "# Start")
        let document = LiveDocument(text: "# Start", fileURL: file.url)
        let repaints = Counter()
        let subscription = document.$bodyHTML.dropFirst().sink { _ in repaints.increment() }
        defer { subscription.cancel() }

        for index in 1...10 { try file.write("# Write \(index)") }

        #expect(await waitUntil { document.bodyHTML.contains("<h1>Write 10</h1>") })
        // Let anything the window might still be holding come through before
        // counting, so a storm can't hide behind the assertion above.
        try await Task.sleep(for: LiveReload.coalescingWindow * 6)

        // Ten writes, one repaint. Two is allowed for the case where the first
        // write's window closed before the rest of the burst arrived; ten
        // would mean the coalescer isn't doing anything.
        #expect(repaints.total >= 1)
        #expect(repaints.total <= 2)
        #expect(document.bodyHTML.contains("<h1>Write 10</h1>"))
    }

    @Test func aRenderedDocumentKeepsItsShellAcrossReloads() async throws {
        // Content updates are injections, never reloads (CONTEXT.md's page
        // shell / body HTML distinction). If a reload ever started reloading
        // the shell, this marker — set on the page after the first paint —
        // would be gone.
        let file = try TempFile(contents: "# Before")
        let document = LiveDocument(text: "# Before", fileURL: file.url)
        let webView = try await loadedWebView(showing: document.bodyHTML)
        _ = try await webView.evaluateJavaScript("window.foliumShellMarker = 'alive'")

        try file.write("# After")
        #expect(await waitUntil { document.bodyHTML.contains("<h1>After</h1>") })
        try await inject(document.bodyHTML, into: webView)

        #expect(try await heading(of: webView) == "After")
        let marker = try await webView.evaluateJavaScript("window.foliumShellMarker") as? String
        #expect(marker == "alive")
    }

    @Test func aFileThatCannotBeWatchedStillOpensAndRenders() async throws {
        // Live-reload is an enhancement to a document that is already on
        // screen; a path Folium can't watch must not cost the user the
        // document.
        let missing = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).md")
        let document = LiveDocument(text: "# Opened anyway", fileURL: missing)

        let webView = try await loadedWebView(showing: document.bodyHTML)

        #expect(try await heading(of: webView) == "Opened anyway")
    }

    // MARK: - Helpers

    /// Polls rather than parking on a notification: the point is to observe the
    /// real timing, and the generous ceiling is there to fail a broken reload,
    /// not to measure a working one (`make bench` owns the latency numbers —
    /// wall-clock gates on shared CI runners measure noise, per CONTEXT.md).
    private func waitUntil(
        within timeout: Duration = .seconds(5),
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    /// Mirrors `MarkdownWebView`: load the static shell once via `loadFileURL`,
    /// then push content in with `evaluateJavaScript`.
    private func loadedWebView(showing bodyHTML: String) async throws -> WKWebView {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1012, height: 800))
        let waiter = NavigationWaiter()
        webView.navigationDelegate = waiter
        webView.loadFileURL(MarkdownPage.pageURL, allowingReadAccessTo: MarkdownPage.resourceBaseURL)
        await waiter.waitUntilFinished()
        try await inject(bodyHTML, into: webView)
        return webView
    }

    private func inject(_ bodyHTML: String, into webView: WKWebView) async throws {
        _ = try await webView.evaluateJavaScript(MarkdownPage.renderBodyScript(bodyHTML: bodyHTML))
    }

    private func heading(of webView: WKWebView) async throws -> String {
        let result = try await webView.evaluateJavaScript("document.querySelector(\"h1\").textContent")
        return (result as? String) ?? ""
    }
}

/// Bridges `WKNavigationDelegate`'s completion callback to `async/await` so a
/// test can wait for the shell to load before injecting content.
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

@MainActor
private final class Counter {
    private(set) var total = 0

    func increment() {
        total += 1
    }
}

/// A Markdown file in its own temporary directory, deleted when the test's
/// reference to it goes away.
private final class TempFile {
    let url: URL
    private let directory: URL

    init(contents: String) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FoliumIntegrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("document.md")
        try write(contents)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func write(_ contents: String) throws {
        try Data(contents.utf8).write(to: url)
    }

    /// Saves the way an editor does: a temporary file renamed over the
    /// original.
    func atomicallyReplace(with contents: String) throws {
        let staging = directory.appendingPathComponent("staging-\(UUID().uuidString)")
        try Data(contents.utf8).write(to: staging)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: staging)
    }
}

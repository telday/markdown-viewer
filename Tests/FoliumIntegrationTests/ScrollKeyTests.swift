import AppKit
import Testing
import WebKit
@testable import Folium

/// Seam tests for the scroll keys of issue #6: a real key event, dispatched
/// through a real responder chain, into a real `WKWebView` showing a real
/// rendered document, asserting the viewport actually moved.
///
/// `ScrollKeyWebView` lives in the coverage-excluded `MarkdownWebView.swift`,
/// so per the Definition of Done its behavior is asserted here. The unit tests
/// already cover which keys mean what; what only this tier can show is that
/// the key reaches us natively at all — the acceptance criterion that capture
/// happens outside the page — and that the JS on the other end moves the
/// document rather than throwing.
///
/// `.serialized` because there is only one keyboard. Swift Testing runs a
/// suite's tests concurrently by default, and with several of these in flight
/// each window makes itself key in turn, after which a key event sent to one
/// window can be delivered to whichever web view is focused instead — visible
/// here as a test that pressed nothing bound finding itself scrolled exactly
/// one key press (72 px) by a neighbour. Nothing about the app is at fault;
/// two windows racing for the keyboard is simply not a situation the real app
/// can be in.
@MainActor
@Suite(.serialized)
struct ScrollKeyTests {
    init() {
        AppKitHost.startIfNeeded()
    }

    @Test func pressingTheDownKeyScrollsTheDocumentDown() async throws {
        let webView = try await loadedWebView()
        defer { webView.window?.close() }

        try press("j", on: webView)

        #expect(await waitUntil { try await scrollOffset(of: webView) > 0 })
    }

    @Test func pressingTheUpKeyScrollsBackTowardTheTop() async throws {
        let webView = try await loadedWebView()
        defer { webView.window?.close() }
        _ = try await webView.evaluateJavaScript("window.scrollTo(0, 2000)")
        let start = try await scrollOffset(of: webView)

        try press("k", on: webView)

        #expect(await waitUntil { try await scrollOffset(of: webView) < start })
    }

    @Test func aRebindingTakesEffectInADocumentAlreadyOnScreen() async throws {
        // Rebinding in Preferences has to reach the windows already open, so
        // the binding is pushed onto the live view rather than read once.
        let webView = try await loadedWebView()
        defer { webView.window?.close() }
        webView.scrollKeys = try #require(ScrollKeyBindings.standard.rebinding(.downward, to: "n"))

        try press("n", on: webView)
        let afterRebound = try await restingOffset(of: webView)
        #expect(afterRebound > 0)

        // And the key it replaced no longer does anything.
        try press("j", on: webView)
        try await settle()
        #expect(try await scrollOffset(of: webView) == afterRebound)
    }

    @Test func anUnboundKeyLeavesTheDocumentWhereItIs() async throws {
        // The failure this guards is a scroll key handler that answers every
        // keystroke, which would take ⌘F, VoiceOver and everything else with
        // it. Nothing has moved because the key went to `super`.
        let webView = try await loadedWebView()
        defer { webView.window?.close() }

        try press("x", on: webView)
        try await settle()

        let offset = try await scrollOffset(of: webView)
        #expect(offset == 0)
    }

    @Test func aModifiedScrollKeyIsLeftForTheRestOfTheSystem() async throws {
        // ⌘J has to stay available as a menu key equivalent.
        let webView = try await loadedWebView()
        defer { webView.window?.close() }

        try press("j", on: webView, modifiers: .command)
        try await settle()

        let offset = try await scrollOffset(of: webView)
        #expect(offset == 0)
    }

    @Test func scrollingIsSmoothRatherThanAJump() async throws {
        // "Smooth scroll motion" is an acceptance criterion, and a jump would
        // pass every other test here. A smooth scroll is still animating one
        // frame after the key press, so it is observably short of where it
        // will end up; scrollBy's instant path would already be there.
        let webView = try await loadedWebView()
        defer { webView.window?.close() }

        try press("j", on: webView)
        try await Task.sleep(for: .milliseconds(16))
        let midFlight = try await scrollOffset(of: webView)

        #expect(await waitUntil { try await scrollOffset(of: webView) > midFlight })
    }

    // MARK: - Helpers

    /// The page `MarkdownWebView` builds, in a window, with the web view as
    /// first responder — so a key event goes where AppKit would really send
    /// it rather than being handed to `keyDown(with:)` directly.
    private func loadedWebView() async throws -> ScrollKeyWebView {
        let webView = ScrollKeyWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        let waiter = NavigationWaiter()
        webView.navigationDelegate = waiter
        webView.loadFileURL(MarkdownPage.pageURL, allowingReadAccessTo: MarkdownPage.resourceBaseURL)
        await waiter.waitUntilFinished()

        // Long enough that there is somewhere to scroll to.
        let markdown = (1...200).map { "Paragraph \($0).\n" }.joined(separator: "\n")
        let body = MarkdownRenderer.renderHTML(from: markdown)
        _ = try await webView.evaluateJavaScript(MarkdownPage.renderBodyScript(bodyHTML: body))

        let window = NSWindow(
            contentRect: webView.frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        // A programmatically created NSWindow releases itself on close, which
        // double-frees once ARC also lets go — a segfault that takes the whole
        // bundle down instead of failing a test.
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(webView)
        return webView
    }

    /// Sends a key press the way the system does: to the window, which routes
    /// it down the responder chain. If `ScrollKeyWebView` ever stopped being
    /// the view that sees the keystroke, these tests would go red — which is
    /// the point of not calling `keyDown(with:)` directly.
    private func press(
        _ characters: String,
        on webView: ScrollKeyWebView,
        modifiers: NSEvent.ModifierFlags = []
    ) throws {
        let window = try #require(webView.window)
        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: 0
            )
        )
        window.sendEvent(event)
    }

    /// Where the document ends up once the smooth scroll has come to rest.
    /// Sampling mid-animation would compare against a number still moving.
    private func restingOffset(of webView: ScrollKeyWebView) async throws -> Double {
        var previous = try await scrollOffset(of: webView)
        for _ in 0..<200 {
            try await Task.sleep(for: .milliseconds(20))
            let current = try await scrollOffset(of: webView)
            if current == previous, current > 0 { return current }
            previous = current
        }
        return previous
    }

    private func scrollOffset(of webView: ScrollKeyWebView) async throws -> Double {
        let result = try await webView.evaluateJavaScript("window.scrollY")
        return (result as? Double) ?? 0
    }

    /// Long enough that a scroll which was going to happen has happened, used
    /// by the tests asserting that nothing moved.
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(400))
    }

    /// Polls: a smooth scroll is an animation, so the assertion is about where
    /// the document ends up, not about a particular frame.
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

/// Bridges WebKit's load-finished callback to `async/await`.
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

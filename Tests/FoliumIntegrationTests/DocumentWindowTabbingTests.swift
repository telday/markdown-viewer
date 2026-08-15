import AppKit
import Testing
@testable import Folium

/// Seam tests for `DocumentWindowTabber` — the glue that turns
/// `DocumentTabbing`'s decisions into real AppKit window tabs (issue #5).
///
/// `DocumentWindowTabber` is on the coverage exclusion list, so per the
/// Definition of Done its behavior is asserted here instead. These drive real
/// `NSWindow`s: the thing worth proving is not that the policy returns a
/// window (unit tests cover that) but that handing that window to
/// `addTabbedWindow(_:ordered:)` genuinely produces **one** window with both
/// documents in a single native tab group — which is what gives issue #5 its
/// drag-to-reorder, drag-out and ⌘W behavior for free.
@MainActor
struct DocumentWindowTabbingTests {
    init() {
        AppKitHost.startIfNeeded()
    }

    @Test func aSecondDocumentWindowBecomesATabOfTheFirst() {
        let first = documentWindow()
        let second = documentWindow()
        defer { close(first, second) }

        DocumentWindowTabber.adopt(first, orderedWindows: [first], userPreference: .inFullScreen)
        DocumentWindowTabber.adopt(second, orderedWindows: [second, first], userPreference: .inFullScreen)

        // One tab group holding both windows is exactly what "two tabs of the
        // same window" is, at the AppKit level.
        #expect(second.tabGroup != nil)
        #expect(second.tabGroup === first.tabGroup)
        #expect(second.tabGroup?.windows.count == 2)
    }

    @Test func aThirdDocumentWindowJoinsTheSameGroupRatherThanStartingAnother() {
        let first = documentWindow()
        let second = documentWindow()
        let third = documentWindow()
        defer { close(first, second, third) }

        DocumentWindowTabber.adopt(first, orderedWindows: [first], userPreference: .inFullScreen)
        DocumentWindowTabber.adopt(second, orderedWindows: [second, first], userPreference: .inFullScreen)
        DocumentWindowTabber.adopt(third, orderedWindows: [third, second, first], userPreference: .inFullScreen)

        #expect(third.tabGroup?.windows.count == 3)
    }

    @Test func adoptingTagsTheWindowSoLaterWindowsCanRecognizeIt() {
        // The tabbing identifier is what makes AppKit willing to merge these
        // windows and what `adopt` looks for when picking a target; without it
        // every window would stand alone no matter what the policy said.
        let window = documentWindow()
        defer { close(window) }

        DocumentWindowTabber.adopt(window, orderedWindows: [window], userPreference: .inFullScreen)

        #expect(window.tabbingIdentifier == DocumentTabbing.tabbingIdentifier)
        #expect(window.tabbingMode == .preferred)
    }

    @Test func windowsStayApartWhenTheUserTurnedAutomaticTabbingOff() {
        let first = documentWindow()
        let second = documentWindow()
        defer { close(first, second) }

        DocumentWindowTabber.adopt(first, orderedWindows: [first], userPreference: .manual)
        DocumentWindowTabber.adopt(second, orderedWindows: [second, first], userPreference: .manual)

        #expect(second.tabbingMode == .automatic)
        #expect((second.tabGroup?.windows.count ?? 1) == 1)
    }

    @Test func aDocumentWindowIsNotTabbedIntoAPanel() {
        // NSApp.orderedWindows carries more than document windows (the Open
        // panel, for one), and only windows `adopt` has tagged are eligible.
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.orderFront(nil)
        let document = documentWindow()
        defer { panel.close(); close(document) }

        DocumentWindowTabber.adopt(document, orderedWindows: [document, panel], userPreference: .inFullScreen)

        #expect((document.tabGroup?.windows.count ?? 1) == 1)
    }

    // MARK: - Helpers

    /// A stand-in for the window `DocumentGroup` creates: same style mask, so
    /// AppKit considers it tabbable at all (a borderless window is not).
    private func documentWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        // A programmatically created NSWindow releases itself on `close()`,
        // which double-frees it once ARC also releases the test's reference —
        // a segfault that takes the whole bundle down rather than failing a
        // test. SwiftUI's own document windows are not released this way.
        window.isReleasedWhenClosed = false
        window.orderFront(nil)
        return window
    }

    private func close(_ windows: NSWindow...) {
        for window in windows { window.close() }
    }
}

/// Brings up the `NSApplication` that AppKit's window tab-group machinery
/// assumes exists. `swift test` runs as a plain command-line process, and
/// without this `addTabbedWindow(_:ordered:)` takes the whole test bundle down
/// with a segfault rather than failing an assertion.
@MainActor
private enum AppKitHost {
    private static var isStarted = false

    static func startIfNeeded() {
        guard !isStarted else { return }
        isStarted = true
        // `.accessory` keeps the suite from stealing focus and putting a Dock
        // icon up on whoever is running it.
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}

import AppKit
import SwiftUI
import Testing
@testable import Folium

/// Seam tests for `PreferencesView` — the Settings window behind ⌘, and the
/// key-capture control in it (issue #6).
///
/// `PreferencesView.swift` is on the coverage exclusion list, so per the
/// Definition of Done its behavior is asserted here. The decisions it defers to
/// (which keys are bindable, what a rebind does to the other direction) are
/// unit-tested; what only this tier can show is that a real key press on a real
/// control in a real window reaches the store — and, in the last test, that
/// SwiftUI actually builds those controls and wires them to the right
/// direction.
///
/// `.serialized` for the same reason as `ScrollKeyTests`: these make windows
/// key and press keys into them, and there is only one keyboard.
@MainActor
@Suite(.serialized)
struct PreferencesTests {
    init() {
        AppKitHost.startIfNeeded()
    }

    // MARK: - The capture control

    @Test func theControlShowsTheKeyThatIsBound() {
        let button = KeyCaptureButton()
        button.boundKey = "j"

        #expect(button.title == "J")
    }

    @Test func clickingItAsksForAKey() {
        let button = hostedButton()
        defer { button.window?.close() }
        button.boundKey = "j"

        click(button)

        #expect(button.title != "J")
        #expect(button.window?.firstResponder === button)
    }

    @Test func theNextKeyPressedIsTheNewBinding() {
        let button = hostedButton()
        defer { button.window?.close() }
        var captured: [String] = []
        button.onCapture = { captured.append($0) }

        click(button)
        press("n", on: button)

        #expect(captured == ["n"])
    }

    @Test func aShiftedKeyIsRecordedAsTheKeyItself() {
        // Otherwise a capture made with Caps Lock on would store "N" and then
        // never match the "n" the user actually presses.
        let button = hostedButton()
        defer { button.window?.close() }
        var captured: [String] = []
        button.onCapture = { captured.append($0) }

        click(button)
        press("N", on: button)

        #expect(captured == ["n"])
    }

    @Test func escapeLeavesTheBindingAlone() {
        // The standard way out of a modal capture on this platform. Escape is
        // rejected as a binding, which is what turns it into the cancel key.
        let button = hostedButton()
        defer { button.window?.close() }
        button.boundKey = "j"
        var captured: [String] = []
        button.onCapture = { captured.append($0) }

        click(button)
        press("\u{1b}", on: button)

        #expect(captured.isEmpty)
        #expect(button.title == "J")
    }

    @Test func clickingAwayStopsItListening() {
        // A control left silently listening would eat the next keystroke the
        // user meant for something else.
        let button = hostedButton()
        defer { button.window?.close() }
        button.boundKey = "j"
        var captured: [String] = []
        button.onCapture = { captured.append($0) }

        click(button)
        button.window?.makeFirstResponder(button.superview)
        press("n", on: button)

        #expect(captured.isEmpty)
        #expect(button.title == "J")
    }

    @Test func keysPressedBeforeItIsClickedAreNotCaptured() {
        let button = hostedButton()
        defer { button.window?.close() }
        var captured: [String] = []
        button.onCapture = { captured.append($0) }

        // Focused, e.g. by tabbing to it, but never clicked.
        button.window?.makeFirstResponder(button)
        press("n", on: button)

        #expect(captured.isEmpty)
    }

    // MARK: - The window as a whole

    @Test func rebindingInThePreferencesWindowChangesTheStoredBindings() throws {
        // The whole feature end to end: SwiftUI builds the Settings content,
        // the control the user clicks is wired to the direction it is labelled
        // with, and the key they press lands in UserDefaults.
        let suite = TemporaryDefaults()
        let store = ScrollKeyStore(defaults: suite.defaults)
        let window = hosting(PreferencesView(scrollKeys: store))
        defer { window.close() }

        let buttons = captureButtons(in: try #require(window.contentView))
        #expect(buttons.count == 2)
        let downButton = try #require(buttons.first)
        #expect(downButton.title == "J")

        click(downButton)
        press("n", on: downButton)

        #expect(store.bindings.downKey == "n")
        #expect(ScrollKeyStore(defaults: suite.defaults).bindings.downKey == "n")
    }

    // MARK: - Helpers

    /// A capture button in a real window, since it can only take focus and
    /// receive key events from inside one.
    private func hostedButton() -> KeyCaptureButton {
        let button = KeyCaptureButton()
        button.frame = NSRect(x: 0, y: 0, width: 80, height: 24)
        let window = keyWindow(contentView: FocusableContainer(frame: NSRect(x: 0, y: 0, width: 200, height: 80)))
        window.contentView?.addSubview(button)
        return button
    }

    /// A SwiftUI view in a real window, laid out, so the `NSViewRepresentable`s
    /// inside it have been made.
    private func hosting(_ view: some View) -> NSWindow {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 240)
        let window = keyWindow(contentView: hostingView)
        hostingView.layoutSubtreeIfNeeded()
        return window
    }

    private func keyWindow(contentView: NSView) -> NSWindow {
        let window = NSWindow(
            contentRect: contentView.frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        // A programmatically created NSWindow releases itself on close, which
        // double-frees once ARC also lets go — a segfault that takes the whole
        // bundle down instead of failing a test.
        window.isReleasedWhenClosed = false
        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func captureButtons(in view: NSView) -> [KeyCaptureButton] {
        (view as? KeyCaptureButton).map { [$0] } ?? view.subviews.flatMap(captureButtons(in:))
    }

    /// Clicks the control by sending its own target/action, which is what a
    /// real click does. `performClick(_:)` would be the obvious call, but it
    /// runs AppKit's button-tracking loop, and unwinding that loop inside a
    /// `swift test` process stops the main run loop — which Swift's async
    /// `main` treats as the program being over, ending the run mid-suite with
    /// no failure and no crash report.
    private func click(_ button: KeyCaptureButton) {
        button.sendAction(button.action, to: button.target)
    }

    /// Sends the key press to the window, so the event travels the responder
    /// chain rather than being handed to `keyDown(with:)` directly.
    private func press(_ characters: String, on button: KeyCaptureButton) {
        guard let window = button.window,
              let event = NSEvent.keyEvent(
                  with: .keyDown,
                  location: .zero,
                  modifierFlags: [],
                  timestamp: ProcessInfo.processInfo.systemUptime,
                  windowNumber: window.windowNumber,
                  context: nil,
                  characters: characters,
                  charactersIgnoringModifiers: characters,
                  isARepeat: false,
                  keyCode: 0
              ) else { return }
        window.sendEvent(event)
    }
}

/// The container the capture button sits in: a plain view, except that it can
/// take the keyboard, so a test can move focus off the button the way clicking
/// another control would.
private final class FocusableContainer: NSView {
    override var acceptsFirstResponder: Bool { true }
}

/// A `UserDefaults` suite of its own, removed when the test's reference to it
/// goes away, so the run never touches the machine's real preferences.
private final class TemporaryDefaults {
    let defaults: UserDefaults
    private let name = "FoliumIntegrationTests-\(UUID().uuidString)"

    init() {
        defaults = UserDefaults(suiteName: name) ?? .standard
    }

    deinit {
        defaults.removePersistentDomain(forName: name)
    }
}

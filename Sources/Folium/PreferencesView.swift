import AppKit
import SwiftUI

/// The contents of Folium's Settings window — the one `FoliumApp`'s `Settings`
/// scene puts behind the standard Settings… item at ⌘, (issue #6).
///
/// Only input and behavior are configurable here, never how a document looks:
/// `CONTEXT.md` priority 3 makes GitHub's rendering the contract rather than a
/// default, so there is no theme, font or width to offer.
struct PreferencesView: View {
    @ObservedObject var scrollKeys: ScrollKeyStore

    var body: some View {
        Form {
            Section("Scrolling") {
                LabeledContent("Scroll down") {
                    KeyCaptureField(key: scrollKeys.bindings.downKey) { key in
                        scrollKeys.bind(.downward, to: key)
                    }
                }
                LabeledContent("Scroll up") {
                    KeyCaptureField(key: scrollKeys.bindings.upKey) { key in
                        scrollKeys.bind(.upward, to: key)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 360)
    }
}

/// A button showing the key currently bound, which listens for the next key
/// press after it's clicked.
///
/// AppKit has no key-capture control to reuse, but it does have the button
/// underneath one — so this is an `NSButton` that intercepts `keyDown` while
/// it holds focus, rather than a control drawn from scratch. The bezel, the
/// focus ring, the pressed state and the accessibility role all come from
/// AppKit (`CONTEXT.md` priority 1).
struct KeyCaptureField: NSViewRepresentable {
    /// The key currently bound to this direction.
    let key: String
    /// Called with a key the user pressed that `ScrollKeyBindings` accepts.
    let onCapture: (String) -> Void

    func makeNSView(context: Context) -> KeyCaptureButton {
        KeyCaptureButton()
    }

    func updateNSView(_ button: KeyCaptureButton, context: Context) {
        button.onCapture = onCapture
        button.boundKey = key
    }
}

/// The `NSButton` behind `KeyCaptureField`.
final class KeyCaptureButton: NSButton {
    /// Called with the captured key, once it has been through
    /// `ScrollKeyBindings.normalized(_:)`.
    var onCapture: ((String) -> Void)?

    /// The key to display when not listening.
    var boundKey: String = "" {
        didSet { if !isListening { showBoundKey() } }
    }

    private var isListening = false

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(startListening)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("KeyCaptureButton is created in code, never from a nib.")
    }

    /// `NSControl` otherwise only accepts focus when Full Keyboard Access is
    /// switched on, and a control whose entire purpose is receiving a key
    /// press has to be able to hold the keyboard regardless.
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isListening else {
            super.keyDown(with: event)
            return
        }
        // A key that can't be bound — Escape, Tab, an arrow — cancels instead
        // of being reported, which is what makes Escape the way out.
        if let key = ScrollKeyBindings.normalized(event.charactersIgnoringModifiers ?? "") {
            onCapture?(key)
        }
        stopListening()
    }

    /// Clicking elsewhere abandons the capture, so the control can't be left
    /// silently swallowing keystrokes.
    override func resignFirstResponder() -> Bool {
        stopListening()
        return super.resignFirstResponder()
    }

    @objc private func startListening() {
        isListening = true
        title = "Press a key…"
        window?.makeFirstResponder(self)
    }

    private func stopListening() {
        isListening = false
        showBoundKey()
    }

    private func showBoundKey() {
        title = boundKey.uppercased()
    }
}

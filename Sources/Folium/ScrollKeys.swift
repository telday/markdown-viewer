import Foundation

/// The direction a scroll key moves the document.
enum ScrollDirection: Equatable {
    case upward
    case downward
}

/// A keystroke, reduced to the two things the scroll-key mapping cares about.
///
/// The AppKit `NSEvent` it comes from is translated in `MarkdownWebView`, so
/// the mapping itself stays plain values a unit test can build by hand.
struct ScrollKeyPress: Equatable {
    /// What the key produces with ⌘/⌃/⌥ ignored — `"j"`, not `"∆"` for ⌥J.
    let characters: String

    /// Whether ⌘, ⌃, or ⌥ was held. Shift is deliberately absent: it is how an
    /// uppercase letter gets typed, and the mapping is case-insensitive.
    let carriesModifier: Bool
}

/// Which key scrolls the document which way (issue #6).
///
/// The mapping is a pure function of a keystroke and the current bindings —
/// no `WKWebView`, no `NSEvent`, no `UserDefaults` — so the behavior that
/// decides whether a key press scrolls at all is unit-tested rather than
/// living in the glue that captures the key. `ScrollKeyStore` persists these;
/// `MarkdownWebView` applies them.
struct ScrollKeyBindings: Equatable {
    /// The key that scrolls toward the end of the document.
    let downKey: String
    /// The key that scrolls toward the start of the document.
    let upKey: String

    /// Vim's `j`/`k`, which is what the audience in `CONTEXT.md` already has
    /// in their fingers.
    static let standard = ScrollKeyBindings(downKey: "j", upKey: "k")

    /// Private so every binding in existence has been through
    /// ``rebinding(_:to:)`` — which is what guarantees both keys are
    /// normalized and that they are never the same key.
    private init(downKey: String, upKey: String) {
        self.downKey = downKey
        self.upKey = upKey
    }

    /// Which way this keystroke scrolls, or `nil` if it isn't a scroll key and
    /// should be left to the rest of the responder chain.
    func direction(for press: ScrollKeyPress) -> ScrollDirection? {
        // ⌘K is a menu equivalent waiting to happen, and ⌥J types a character.
        // Only the bare key scrolls.
        guard !press.carriesModifier else { return nil }
        guard let key = Self.normalized(press.characters) else { return nil }

        switch key {
        case downKey: return .downward
        case upKey: return .upward
        default: return nil
        }
    }

    /// These bindings with `direction` moved to `key`, or `nil` if `key` isn't
    /// a key that can be bound.
    ///
    /// Binding one direction to the key the *other* direction already has
    /// swaps them, rather than leaving a document that can only be scrolled
    /// one way — the same thing a game's control panel does, and the reason
    /// duplicate bindings are unrepresentable.
    func rebinding(_ direction: ScrollDirection, to key: String) -> ScrollKeyBindings? {
        guard let key = Self.normalized(key) else { return nil }
        switch direction {
        case .downward:
            return ScrollKeyBindings(downKey: key, upKey: key == upKey ? downKey : upKey)
        case .upward:
            return ScrollKeyBindings(downKey: key == downKey ? upKey : downKey, upKey: key)
        }
    }

    /// The bindings a stored pair of keys describes, falling back to
    /// ``standard`` for whatever part of the pair is missing or unusable.
    ///
    /// Nothing a user can do to the preferences file — hand-editing it to an
    /// arrow key, to two spaces, or to the same letter twice — may leave the
    /// document unscrollable, so a rejected value simply doesn't apply.
    static func restoring(downKey: String?, upKey: String?) -> ScrollKeyBindings {
        var bindings = standard
        if let downKey { bindings = bindings.rebinding(.downward, to: downKey) ?? bindings }
        if let upKey { bindings = bindings.rebinding(.upward, to: upKey) ?? bindings }
        return bindings
    }

    /// A single bindable character from what a key produced, or `nil` if that
    /// key can't be a scroll key.
    ///
    /// Rejected, and why:
    ///
    /// - **Control characters** — Escape, Tab and Return are how the user gets
    ///   *out* of the key-capture control and around the window.
    /// - **Whitespace** — Space is the standard page-down key everywhere on
    ///   this platform, and a binding the user cannot see is a trap.
    /// - **`U+F700`–`U+F8FF`** — AppKit reports arrow and function keys as
    ///   characters in that private-use block. Arrows already scroll a
    ///   `WKWebView` on their own, so binding one would either do nothing new
    ///   or take an existing affordance away.
    ///
    /// Lowercased, so a binding made with Caps Lock on still matches the key
    /// pressed without it.
    static func normalized(_ characters: String) -> String? {
        let lowercased = characters.lowercased()
        guard lowercased.count == 1, let scalar = lowercased.unicodeScalars.first else { return nil }
        guard !CharacterSet.controlCharacters.contains(scalar),
              !CharacterSet.whitespacesAndNewlines.contains(scalar),
              !(0xF700...0xF8FF).contains(scalar.value) else { return nil }
        return lowercased
    }
}

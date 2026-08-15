import Testing
@testable import Folium

/// Unit tests for the key-to-scroll-action mapping behind issue #6, which the
/// issue asks to be testable without a live `WKWebView` — so every case here
/// is a plain `ScrollKeyPress` against plain bindings. The AppKit half (a real
/// key press reaching the web view and moving the viewport) is
/// `ScrollKeyTests` in the integration target.
struct ScrollKeysTests {
    // MARK: - The default bindings

    @Test func theDefaultBindingsAreVimsJAndK() {
        #expect(ScrollKeyBindings.standard.downKey == "j")
        #expect(ScrollKeyBindings.standard.upKey == "k")
    }

    // MARK: - direction(for:)

    @Test func theDownKeyScrollsDownAndTheUpKeyScrollsUp() {
        let bindings = ScrollKeyBindings.standard

        #expect(bindings.direction(for: .press("j")) == .downward)
        #expect(bindings.direction(for: .press("k")) == .upward)
    }

    @Test func anUnboundKeyIsLeftToTheRestOfTheResponderChain() {
        // nil is what makes the web view hand the key to `super`, so this is
        // the assertion standing between a scroll key and swallowing every
        // other keystroke in the app.
        #expect(ScrollKeyBindings.standard.direction(for: .press("x")) == nil)
    }

    @Test func aRebindingIsWhatTheKeyPressIsMatchedAgainst() {
        let bindings = ScrollKeyBindings.standard.rebinding(.downward, to: "n")

        #expect(bindings?.direction(for: .press("n")) == .downward)
        #expect(bindings?.direction(for: .press("j")) == nil)
    }

    @Test func holdingAModifierNeverScrolls() {
        // ⌘J is a menu key equivalent waiting to be added, and ⌃J/⌥J belong to
        // AppKit's own text bindings. Scrolling on them would quietly steal
        // keystrokes the rest of the system expects to get.
        let bindings = ScrollKeyBindings.standard

        #expect(bindings.direction(for: ScrollKeyPress(characters: "j", carriesModifier: true)) == nil)
        #expect(bindings.direction(for: ScrollKeyPress(characters: "k", carriesModifier: true)) == nil)
    }

    @Test func shiftedAndCapsLockedKeysStillScroll() {
        // Shift is not treated as a modifier: with Caps Lock on, AppKit reports
        // "J", and a document that stops scrolling until you notice the light
        // is on would read as a bug.
        #expect(ScrollKeyBindings.standard.direction(for: .press("J")) == .downward)
    }

    @Test func aKeyThatProducesNoCharactersIsNotAScrollKey() {
        // Pressing ⌘ or ⇧ on its own reports an empty string.
        #expect(ScrollKeyBindings.standard.direction(for: .press("")) == nil)
    }

    // MARK: - rebinding(_:to:)

    @Test func rebindingOneDirectionLeavesTheOtherAlone() {
        let bindings = ScrollKeyBindings.standard.rebinding(.upward, to: "p")

        #expect(bindings?.upKey == "p")
        #expect(bindings?.downKey == "j")
    }

    @Test func bindingADirectionToTheOtherDirectionsKeySwapsThem() {
        // Otherwise one direction would become unreachable, and the user would
        // have a document they can only scroll one way.
        let bindings = ScrollKeyBindings.standard.rebinding(.downward, to: "k")

        #expect(bindings?.downKey == "k")
        #expect(bindings?.upKey == "j")
    }

    @Test func rebindingADirectionToTheKeyItAlreadyHasChangesNothing() {
        let bindings = ScrollKeyBindings.standard.rebinding(.downward, to: "j")

        #expect(bindings == ScrollKeyBindings.standard)
    }

    @Test func aKeyIsStoredLowercasedSoItMatchesEitherWay() {
        let bindings = ScrollKeyBindings.standard.rebinding(.downward, to: "N")

        #expect(bindings?.downKey == "n")
        #expect(bindings?.direction(for: .press("n")) == .downward)
    }

    @Test func unbindableKeysAreRefusedRatherThanApplied() {
        let bindings = ScrollKeyBindings.standard

        // Escape and Tab are how the user gets out of the capture control;
        // Space is the system's page-down; the arrow keys already scroll a web
        // view, and AppKit reports them in a private-use block.
        #expect(bindings.rebinding(.downward, to: "\u{1b}") == nil)
        #expect(bindings.rebinding(.downward, to: "\t") == nil)
        #expect(bindings.rebinding(.downward, to: "\r") == nil)
        #expect(bindings.rebinding(.downward, to: " ") == nil)
        #expect(bindings.rebinding(.downward, to: "\u{F701}") == nil)
        #expect(bindings.rebinding(.downward, to: "") == nil)
        #expect(bindings.rebinding(.downward, to: "jk") == nil)
    }

    @Test func anyOtherPrintableKeyCanBeBound() {
        // Including one that isn't a letter — nothing about the mapping is
        // specific to a Latin keyboard.
        #expect(ScrollKeyBindings.standard.rebinding(.downward, to: "/")?.downKey == "/")
        #expect(ScrollKeyBindings.standard.rebinding(.upward, to: "ж")?.upKey == "ж")
    }

    // MARK: - restoring(downKey:upKey:)

    @Test func storedKeysComeBackAsTheBindingsTheyWere() {
        let bindings = ScrollKeyBindings.restoring(downKey: "s", upKey: "w")

        #expect(bindings.downKey == "s")
        #expect(bindings.upKey == "w")
    }

    @Test func aStoredSwapSurvivesTheRoundTrip() {
        // Swapped bindings are the case where restoring naively, one key at a
        // time, could re-swap them back on the way in.
        let swapped = ScrollKeyBindings.standard.rebinding(.downward, to: "k")

        let restored = ScrollKeyBindings.restoring(downKey: swapped?.downKey, upKey: swapped?.upKey)

        #expect(restored == swapped)
    }

    @Test func nothingStoredMeansTheDefaults() {
        #expect(ScrollKeyBindings.restoring(downKey: nil, upKey: nil) == .standard)
    }

    @Test func aStoredValueThatCannotBeBoundFallsBackRatherThanBreakingScrolling() {
        // The preferences file is a text file a user can edit by hand. Whatever
        // ends up in it, the document still has to scroll.
        let bindings = ScrollKeyBindings.restoring(downKey: " ", upKey: "w")

        #expect(bindings.downKey == "j")
        #expect(bindings.upKey == "w")

        // And the same for the other direction, since each is restored on its
        // own and only one of the two paths would otherwise be exercised.
        let other = ScrollKeyBindings.restoring(downKey: "s", upKey: "\u{F700}")

        #expect(other.downKey == "s")
        #expect(other.upKey == "k")
    }

    @Test func twoStoredKeysThatAreTheSameStillLeaveBothDirectionsReachable() {
        let bindings = ScrollKeyBindings.restoring(downKey: "n", upKey: "n")

        #expect(bindings.direction(for: .press("n")) != nil)
        #expect(bindings.downKey != bindings.upKey)
    }
}

private extension ScrollKeyPress {
    /// An ordinary, unmodified key press.
    static func press(_ characters: String) -> Self {
        Self(characters: characters, carriesModifier: false)
    }
}

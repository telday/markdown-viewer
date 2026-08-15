import Combine
import Foundation
import Testing
@testable import Folium

/// Unit tests for the persistence half of issue #6 — "rebound keys persist
/// across app relaunches." A relaunch is modelled as a second `ScrollKeyStore`
/// reading the same defaults suite, which is exactly what the app does at
/// launch.
///
/// Each test gets a throwaway suite so the run never touches the machine's real
/// preferences.
@MainActor
struct ScrollKeyStoreTests {
    @Test func aFreshInstallScrollsWithTheDefaultKeys() {
        let suite = TemporaryDefaults()

        #expect(ScrollKeyStore(defaults: suite.defaults).bindings == .standard)
    }

    @Test func aReboundKeySurvivesARelaunch() {
        let suite = TemporaryDefaults()
        ScrollKeyStore(defaults: suite.defaults).bind(.downward, to: "n")

        let afterRelaunch = ScrollKeyStore(defaults: suite.defaults)

        #expect(afterRelaunch.bindings.downKey == "n")
        #expect(afterRelaunch.bindings.direction(for: press("n")) == .downward)
    }

    @Test func aSwapSurvivesARelaunchInBothDirections() {
        // Binding down to the up key swaps them, so this stores a pair neither
        // of which is a default — the case where writing only the key that
        // changed would come back wrong.
        let suite = TemporaryDefaults()
        ScrollKeyStore(defaults: suite.defaults).bind(.downward, to: "k")

        let afterRelaunch = ScrollKeyStore(defaults: suite.defaults)

        #expect(afterRelaunch.bindings.downKey == "k")
        #expect(afterRelaunch.bindings.upKey == "j")
    }

    @Test func bindingAnUnusableKeyIsRefusedAndChangesNothing() {
        let suite = TemporaryDefaults()
        let store = ScrollKeyStore(defaults: suite.defaults)

        #expect(store.bind(.downward, to: "\u{1b}") == false)
        #expect(store.bindings == .standard)
    }

    @Test func aHandEditedPreferenceIsHonored() {
        // `defaults write com.telday.Folium ScrollDownKey -string 'n'` is a
        // supported way to set this, which is why the keys are named the way
        // they are.
        let suite = TemporaryDefaults()
        suite.defaults.set("n", forKey: ScrollKeyStore.downDefaultsKey)

        #expect(ScrollKeyStore(defaults: suite.defaults).bindings.downKey == "n")
    }

    @Test func theRegisteredDefaultsAreTheStandardBindings() {
        // Registered rather than written, so the values show up in `defaults
        // read` without overwriting a user who set their own.
        #expect(ScrollKeyStore.registrationDefaults[ScrollKeyStore.downDefaultsKey] == "j")
        #expect(ScrollKeyStore.registrationDefaults[ScrollKeyStore.upDefaultsKey] == "k")
    }

    @Test func rebindingPublishesSoOpenDocumentsPickItUp() {
        // Documents already on screen observe this; without the publish, a
        // rebind would only take effect on the next document opened.
        let suite = TemporaryDefaults()
        let store = ScrollKeyStore(defaults: suite.defaults)
        var published: [ScrollKeyBindings] = []
        let subscription = store.$bindings.dropFirst().sink { published.append($0) }
        defer { subscription.cancel() }

        store.bind(.upward, to: "p")

        #expect(published.map(\.upKey) == ["p"])
    }

    private func press(_ characters: String) -> ScrollKeyPress {
        ScrollKeyPress(characters: characters, carriesModifier: false)
    }
}

/// A `UserDefaults` suite of its own, removed when the test's reference to it
/// goes away. Without the removal these accumulate as real preference files on
/// whoever ran the suite.
private final class TemporaryDefaults {
    let defaults: UserDefaults
    private let name = "FoliumTests-\(UUID().uuidString)"

    init() {
        defaults = UserDefaults(suiteName: name) ?? .standard
    }

    deinit {
        defaults.removePersistentDomain(forName: name)
    }
}

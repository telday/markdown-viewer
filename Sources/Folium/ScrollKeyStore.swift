import Combine
import Foundation

/// The app's scroll-key bindings, kept in `UserDefaults` so a rebind survives
/// a relaunch (issue #6).
///
/// One instance is shared by every open document and by the Preferences
/// window: rebinding a key in Preferences has to take effect in the documents
/// already on screen, not just the next one opened.
///
/// `UserDefaults` is Foundation, not AppKit, so this stays in the unit-tested
/// logic layer and its tests drive it with a throwaway suite rather than the
/// machine's real preferences.
@MainActor
final class ScrollKeyStore: ObservableObject {
    /// Defaults keys, spelled the way a user would type them at a terminal:
    /// `defaults write com.telday.Folium ScrollDownKey -string 'n'`.
    static let downDefaultsKey = "ScrollDownKey"
    static let upDefaultsKey = "ScrollUpKey"

    /// Defaults to *register* at launch, not to write — the same reasoning as
    /// `DocumentRestoration.registrationDefaults`. Registering them is what
    /// makes the bindings discoverable in `defaults read`, rather than the
    /// absence of a value standing in for the default.
    static let registrationDefaults: [String: String] = [
        downDefaultsKey: ScrollKeyBindings.standard.downKey,
        upDefaultsKey: ScrollKeyBindings.standard.upKey
    ]

    @Published private(set) var bindings: ScrollKeyBindings

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        bindings = .restoring(
            downKey: defaults.string(forKey: Self.downDefaultsKey),
            upKey: defaults.string(forKey: Self.upDefaultsKey)
        )
    }

    /// Points `direction` at `key`, persisting the result. Returns `false` —
    /// leaving the bindings alone — for a key that can't be bound.
    ///
    /// Both keys are written, not just the one that changed: rebinding can
    /// swap them (see ``ScrollKeyBindings/rebinding(_:to:)``).
    @discardableResult
    func bind(_ direction: ScrollDirection, to key: String) -> Bool {
        guard let updated = bindings.rebinding(direction, to: key) else { return false }
        bindings = updated
        defaults.set(updated.downKey, forKey: Self.downDefaultsKey)
        defaults.set(updated.upKey, forKey: Self.upDefaultsKey)
        return true
    }
}

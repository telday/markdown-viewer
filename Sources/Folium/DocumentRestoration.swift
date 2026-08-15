/// The launch-time settings that make Folium reopen the documents that were
/// open when it was last quit (issue #5).
///
/// Restoring open documents is standard document-app behavior, but a SwiftUI
/// `DocumentGroup` app gets it only if two conditions hold, and neither is the
/// default:
///
/// 1. `NSApplicationDelegate.applicationSupportsSecureRestorableState(_:)`
///    returns `true` — since macOS 12 AppKit refuses to persist state for apps
///    that haven't opted into secure coding for it, and SwiftUI's built-in app
///    delegate does not opt in.
/// 2. ``quitAlwaysKeepsWindowsKey`` is set — otherwise AppKit follows System
///    Settings ▸ Desktop & Dock ▸ "Close windows when quitting an application",
///    which is on by default and throws the open documents away at quit.
///
/// Both were confirmed necessary by testing the built app: with either one
/// missing, relaunching after a quit comes up with an empty Open panel instead
/// of the documents that were open.
///
/// This file holds the values and the reasoning with no AppKit dependency, so
/// it stays in the unit-tested logic layer; `FoliumAppDelegate` is the glue
/// that applies them.
enum DocumentRestoration {
    /// The user default AppKit consults when deciding whether a quit discards
    /// the app's windows.
    static let quitAlwaysKeepsWindowsKey = "NSQuitAlwaysKeepsWindows"

    /// Defaults to *register* at launch — deliberately not to *write*.
    ///
    /// Registration is the lowest-priority defaults domain, so this changes
    /// what Folium does out of the box while leaving a user who genuinely
    /// wants a clean slate on every launch able to say so
    /// (`defaults write com.telday.Folium NSQuitAlwaysKeepsWindows -bool
    /// false`) and be obeyed. Writing the value instead would take that away.
    static let registrationDefaults: [String: Bool] = [quitAlwaysKeepsWindowsKey: true]
}

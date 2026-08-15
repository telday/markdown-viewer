import AppKit

/// The `NSApplication` that AppKit assumes exists, brought up for the tests
/// that drive real windows, real key events and real tab groups.
///
/// `swift test` runs as a plain command-line process, with no application
/// behind the windows a test creates.
///
/// Without it, `addTabbedWindow(_:ordered:)` takes the whole test bundle down
/// with a segfault rather than failing an assertion.
@MainActor
enum AppKitHost {
    private static var isStarted = false

    static func startIfNeeded() {
        guard !isStarted else { return }
        isStarted = true
        // `.accessory` keeps the suite from stealing focus and putting a Dock
        // icon up on whoever is running it.
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}

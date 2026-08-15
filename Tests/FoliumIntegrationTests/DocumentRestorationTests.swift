import AppKit
import Testing
@testable import Folium

/// Seam tests for `FoliumAppDelegate`, which is on the coverage exclusion list
/// and so owes its coverage here (issue #5).
///
/// Both assertions guard a setting that fails *silently*: with either one
/// missing, the app still launches, still opens files, and simply comes up
/// empty after a quit instead of reopening what was open. Verified against the
/// built app both ways before these were written.
@MainActor
struct DocumentRestorationTests {
    @Test func launchingRegistersTheKeepWindowsDefault() {
        let delegate = FoliumAppDelegate()

        delegate.applicationWillFinishLaunching(
            Notification(name: NSApplication.willFinishLaunchingNotification)
        )

        #expect(UserDefaults.standard.bool(forKey: DocumentRestoration.quitAlwaysKeepsWindowsKey))
    }

    @Test func theAppOptsIntoSecureRestorableState() {
        // AppKit persists nothing at all for an app that answers `false` here,
        // so restoration is off before this ever reaches a window.
        #expect(FoliumAppDelegate().applicationSupportsSecureRestorableState(NSApplication.shared))
    }
}

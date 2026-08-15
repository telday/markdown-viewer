import AppKit
import Foundation

/// Opts Folium into AppKit's document/window state restoration, which a
/// SwiftUI `DocumentGroup` app does not get by default (issue #5), and puts
/// the app's out-of-the-box preferences in place.
///
/// Host glue: it exists only to answer AppKit at launch. The settings it
/// applies, and why each is required, live in `DocumentRestoration` and
/// `ScrollKeyStore` in the logic layer.
final class FoliumAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: DocumentRestoration.registrationDefaults)
        UserDefaults.standard.register(defaults: ScrollKeyStore.registrationDefaults)
    }

    /// Folium keeps no secrets in its restorable state — a document window
    /// records which file it shows — and secure coding is what AppKit requires
    /// before it will persist any of it.
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}

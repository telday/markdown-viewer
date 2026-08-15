import AppKit
import SwiftUI

/// Files every document window into Folium's single native tab group, so
/// opening several Markdown files at once reads the way Safari/Finder/Xcode
/// read (ADR 0004, issue #5).
///
/// This is host glue by necessity: SwiftUI's `DocumentGroup` never hands the
/// app the `NSWindow` it created, so the only way to reach it is from inside
/// the document's own view tree — a zero-size `NSView` that notices which
/// window it was added to. All the *decisions* live in `DocumentTabbing`, in
/// the unit-tested logic layer; what's left here is reading AppKit state and
/// calling `addTabbedWindow(_:ordered:)`, which is the real system tab
/// mechanism (CONTEXT.md priority 1: never reimplement what AppKit provides —
/// dragging to reorder, dragging a tab out, ⌘W, and Mission Control all come
/// with it).
struct DocumentWindowTabber: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        TabbingHostView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    /// Adopts `window` into the tab group, given the app's windows front to
    /// back. Takes both as parameters rather than reading `NSApp` so the
    /// integration tests can drive it with windows they control.
    @MainActor
    static func adopt(
        _ window: NSWindow,
        orderedWindows: [NSWindow],
        userPreference: NSWindow.UserTabbingPreference = NSWindow.userTabbingPreference
    ) {
        let prefersTabbing = DocumentTabbing.prefersTabbing(userPreference: .init(userPreference))

        // Identify the window as ours before looking for a target, so the
        // *next* window to open can find this one.
        window.tabbingIdentifier = DocumentTabbing.tabbingIdentifier
        window.tabbingMode = prefersTabbing ? .preferred : .automatic

        let candidates = orderedWindows.filter { $0 !== window }.map { other in
            DocumentTabbing.Candidate(
                window: other,
                isDocumentWindow: other.tabbingIdentifier == DocumentTabbing.tabbingIdentifier,
                isVisible: other.isVisible
            )
        }
        let target = DocumentTabbing.mergeTarget(
            prefersTabbing: prefersTabbing,
            // A group of one is just this window; only a group with something
            // else in it means AppKit (or the user) already tabbed it.
            newWindowIsAlreadyTabbed: (window.tabGroup?.windows.count ?? 1) > 1,
            orderedOtherWindows: candidates
        )
        target?.addTabbedWindow(window, ordered: .above)
    }

    /// A zero-size view whose only job is to report the window it landed in.
    ///
    /// The work happens in `viewDidMoveToWindow` rather than on a later
    /// runloop turn deliberately: by the time an asynchronous hop ran, the
    /// window would already have been ordered in as a separate window, and the
    /// merge would read as a visible flash.
    private final class TabbingHostView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            DocumentWindowTabber.adopt(window, orderedWindows: NSApp.orderedWindows)
        }
    }
}

extension DocumentTabbing.UserPreference {
    /// Mirrors AppKit's setting into the logic layer's AppKit-free vocabulary.
    /// `@unknown default` maps to the macOS default rather than the opt-out:
    /// a value we don't recognize is not evidence the user asked for no tabs.
    init(_ preference: NSWindow.UserTabbingPreference) {
        switch preference {
        case .manual: self = .manual
        case .inFullScreen: self = .inFullScreen
        case .always: self = .always
        @unknown default: self = .inFullScreen
        }
    }
}

/// Decides how Folium's document windows become native macOS window tabs
/// (ADR 0004).
///
/// `DocumentGroup` gives each open file a real `NSWindow`, but AppKit only
/// *merges* those windows into one tabbed window when the window asks it to.
/// A window left at `.automatic` follows the system-wide "Prefer tabs when
/// opening documents" setting, whose default is *In Full Screen Only* — so out
/// of the box, opening three Markdown files scatters three separate windows
/// across the desktop instead of tabbing them.
///
/// This type holds the two decisions that fixes: whether a window should prefer
/// tabbing at all, and which already-open window a new one should join.
/// Everything here is plain values with no AppKit dependency, so it lives in the
/// unit-tested logic layer; `DocumentWindowTabber` is the thin `NSWindow` glue
/// that applies the answers.
enum DocumentTabbing {
    /// AppKit only merges windows that share a tabbing identifier, so every
    /// Folium document window carries this one and no other window does.
    static let tabbingIdentifier = "com.telday.Folium.document"

    /// The user's system-wide "Prefer tabs when opening documents" setting,
    /// mirrored from `NSWindow.UserTabbingPreference` so this file stays
    /// AppKit-free.
    enum UserPreference {
        /// "Never" — the user opted out of automatic tabbing system-wide.
        case manual
        /// "In Full Screen Only" — the macOS default.
        case inFullScreen
        /// "Always".
        case always
    }

    /// An already-open window a new document window could be added to.
    ///
    /// Generic over the window type so the policy never names `NSWindow`: the
    /// glue passes real windows in and gets one back to call
    /// `addTabbedWindow(_:ordered:)` on.
    struct Candidate<Window> {
        let window: Window
        /// Whether this is one of Folium's document windows — i.e. it carries
        /// ``tabbingIdentifier``. Screens out panels, the Open dialog, and
        /// anything else AppKit has on screen.
        let isDocumentWindow: Bool
        /// Off-screen windows (closed-but-not-deallocated, minimized away) are
        /// not somewhere a new tab should be filed.
        let isVisible: Bool
    }

    /// Whether Folium should push its document windows into a shared tab group.
    ///
    /// Folium overrides the `.inFullScreen` default: a viewer opened on several
    /// files at once is precisely the case window tabs exist for, and issue #5
    /// requires multiple files to arrive as tabs rather than loose windows.
    ///
    /// `.manual` is left alone. That value is not a default — it is a user who
    /// went into System Settings and asked never to have windows tabbed for
    /// them, and priority 1 (native Mac citizen) means an explicit system-level
    /// choice outranks our preference. Those users still get tabs the standard
    /// way, via Window ▸ Merge All Windows.
    static func prefersTabbing(userPreference: UserPreference) -> Bool {
        userPreference != .manual
    }

    /// The window a newly opened document window should be added to as a tab,
    /// or `nil` if it should stand on its own.
    ///
    /// - Parameters:
    ///   - prefersTabbing: the result of ``prefersTabbing(userPreference:)``.
    ///   - newWindowIsAlreadyTabbed: whether AppKit already placed the new
    ///     window in a tab group with something else. Merging again would be
    ///     both redundant and a way to yank a window out of the group the user
    ///     just dragged it into.
    ///   - orderedOtherWindows: every *other* window the app has, front to back.
    ///     Front-most first is what makes a new tab land in the window the user
    ///     is actually looking at when several tab groups are open.
    static func mergeTarget<Window>(
        prefersTabbing: Bool,
        newWindowIsAlreadyTabbed: Bool,
        orderedOtherWindows: [Candidate<Window>]
    ) -> Window? {
        guard prefersTabbing, !newWindowIsAlreadyTabbed else { return nil }
        return orderedOtherWindows.first { $0.isDocumentWindow && $0.isVisible }?.window
    }
}

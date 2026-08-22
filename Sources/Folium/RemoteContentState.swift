import Combine

/// One open document's remote-content opt-in (issue #19): whether its
/// rendered body references content the strict CSP blocks, and whether this
/// document's user has chosen to load it anyway.
///
/// `ObservableObject` (from `Combine`, not SwiftUI) so `DocumentView` can
/// hold one per document and have the native "Load" bar and the web view's
/// shell choice both follow it, without either importing AppKit/WebKit
/// themselves. Owned alongside `LiveDocument` rather than inside it, so this
/// file and that one can change independently.
///
/// The opt-in is deliberately **not persisted anywhere** — not on this
/// object, not in `UserDefaults`. A new `RemoteContentState` is created each
/// time a document window opens, so closing and reopening a file blocks its
/// remote content again. That is the conservative reading of a security
/// floor (CONTEXT.md's no-network floor), and it matches the mail-client
/// pattern the issue cites: trusting one message doesn't trust every future
/// one from the same sender automatically.
final class RemoteContentState: ObservableObject {
    /// Whether the document's current rendered body references content the
    /// strict shell's CSP blocks. Recomputed on every render, so a live
    /// reload (issue #7) that adds or removes a remote image keeps this
    /// accurate without the user re-opening the file.
    @Published private(set) var hasBlockedContent: Bool

    /// Whether this document's user clicked "Load". One-way for the
    /// lifetime of this object — see `allow()`.
    @Published private(set) var isAllowed = false

    /// Whether `DocumentView`'s "Load remote images" bar should be on
    /// screen. Kept here rather than as an inline condition in
    /// `FoliumApp.swift` — coverage-excluded host glue — because it is a
    /// branching rule on this type's own state, and this file is not
    /// excluded: keeping it here is what makes it unit-testable at all.
    var shouldPromptToLoad: Bool {
        hasBlockedContent && !isAllowed
    }

    /// - Parameter bodyHTML: the document's rendered body at the time this
    ///   state is created, so the initial bar visibility is correct on first
    ///   render rather than only from the next one.
    init(bodyHTML: String = "") {
        hasBlockedContent = RemoteContent.isReferenced(in: bodyHTML)
    }

    /// Call whenever the document body re-renders. Only `hasBlockedContent`
    /// is recomputed — `isAllowed` is left alone, so an opt-in already given
    /// for this document survives a live reload of the same file. Reversing
    /// that (re-blocking on every keystroke of a live-edited file) would make
    /// the "Load" button impossible to trust: it would stop meaning anything
    /// the moment the file changed on disk.
    func render(bodyHTML: String) {
        hasBlockedContent = RemoteContent.isReferenced(in: bodyHTML)
    }

    /// Records that this document's user opted in to loading its remote
    /// content. One-way: nothing in this app ever calls this to turn
    /// `isAllowed` back off for a still-open document. The only way remote
    /// content is blocked again is a new `RemoteContentState` — i.e.
    /// closing and reopening the document.
    func allow() {
        isAllowed = true
    }
}

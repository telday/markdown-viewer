/// The policy behind live-reload: what each kind of file-system notification
/// means, and how long a burst of writes is allowed to settle before the
/// document is re-read (issue #7). `FileWatcher` applies it.
enum LiveReload {
    /// How long to wait after the first notification in a burst before
    /// re-reading the file.
    ///
    /// Spent out of CONTEXT.md's 100 ms "file written → repainted" budget, so
    /// it has to be small — but not zero: one save is usually several writes,
    /// and reacting to each would storm the render path and risk reading a
    /// half-written file. 50 ms covers a normal save and leaves half the budget
    /// for the read and the render.
    static let coalescingWindow: Duration = .milliseconds(50)

    /// What happened to the watched path. Mirrors the file-system events
    /// Folium subscribes to, keeping this file free of Dispatch.
    struct Change: OptionSet, Sendable {
        let rawValue: UInt

        init(rawValue: UInt) {
            self.rawValue = rawValue
        }

        /// The file's contents were modified in place.
        static let written = Change(rawValue: 1 << 0)
        /// The file grew: an append rather than a rewrite.
        static let extended = Change(rawValue: 1 << 1)
        /// The path was renamed, so it no longer names the file we opened.
        static let renamed = Change(rawValue: 1 << 2)
        /// The file was unlinked.
        static let deleted = Change(rawValue: 1 << 3)
        /// The volume holding the file went away — it was ejected.
        static let revoked = Change(rawValue: 1 << 4)

        /// The path no longer names the file the watch has open.
        static let replacements: Change = [.renamed, .deleted, .revoked]
        /// The file the watch has open has new bytes.
        static let edits: Change = [.written, .extended]
    }

    /// What to do about a notification.
    struct Reaction: Equatable {
        /// Whether the document should be re-read and re-rendered.
        let reloads: Bool
        /// Whether the watch has to be re-established against the path.
        let reopens: Bool
    }

    /// Decides how to respond to a notification.
    ///
    /// What makes this more than a pass-through is the **atomic save**, how
    /// most editors write: content goes to a temporary file, which is then
    /// renamed over the original. The path now names a different file, while
    /// the watch still holds the old one — so it would report the first save
    /// and then go silent forever. A rename or delete therefore means both
    /// "re-read" *and* "re-open the path".
    static func reaction(to change: Change) -> Reaction {
        Reaction(
            reloads: !change.isDisjoint(with: .replacements) || !change.isDisjoint(with: .edits),
            reopens: !change.isDisjoint(with: .replacements)
        )
    }

    /// How many times re-opening the path is retried before the watch is
    /// given up on.
    ///
    /// A rename is atomic, so the path is usually already there. Editors that
    /// delete before writing leave a gap, which the retries cover. Bounded so
    /// that a file which is simply gone doesn't leave a timer running for the
    /// life of the window; after that the document keeps what it last read.
    static let reopenAttempts = 10

    /// How long to wait between re-open attempts. See ``reopenAttempts``.
    static let reopenRetryDelay: Duration = .milliseconds(20)
}

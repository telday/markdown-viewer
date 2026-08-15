/// The policy behind live-reload: how long a burst of writes is allowed to
/// settle before the document is re-read, and what each kind of file-system
/// notification means (issue #7).
///
/// Plain values and a pure function with no Dispatch/AppKit dependency, so the
/// decisions live in the unit-tested logic layer; `FileWatcher` is the thin
/// `DispatchSource` glue that applies them.
enum LiveReload {
    /// How long to wait after the first notification in a burst before
    /// re-reading the file.
    ///
    /// This is spent directly out of `CONTEXT.md`'s 100 ms "file written →
    /// repainted" budget, which is why it is small. It cannot be zero: an
    /// editor's save is rarely one write (truncate, write, `fsync`, chmod), and
    /// re-reading on each of them would both storm the render path and risk
    /// showing a half-written file. 50 ms is long enough to swallow a normal
    /// save's event burst and still leave half the budget for read + render.
    static let coalescingWindow: Duration = .milliseconds(50)

    /// What the file system says happened to the watched path. Mirrors the
    /// subset of `DispatchSource.FileSystemEvent` Folium subscribes to, so this
    /// file stays Dispatch-free.
    struct Change: OptionSet, Sendable {
        let rawValue: UInt

        init(rawValue: UInt) {
            self.rawValue = rawValue
        }

        /// The file's contents were modified in place.
        static let written = Change(rawValue: 1 << 0)
        /// The file grew — an append rather than a rewrite.
        static let extended = Change(rawValue: 1 << 1)
        /// The path was renamed out from under the open descriptor.
        static let renamed = Change(rawValue: 1 << 2)
        /// The file was unlinked.
        static let deleted = Change(rawValue: 1 << 3)
        /// The file system backing the file went away (an ejected volume).
        static let revoked = Change(rawValue: 1 << 4)

        /// The changes that mean the *path* no longer refers to the inode the
        /// watch is holding open.
        static let replacements: Change = [.renamed, .deleted, .revoked]
        /// The changes that mean the watched inode itself has new bytes.
        static let edits: Change = [.written, .extended]
    }

    /// What to do about a notification.
    struct Reaction: Equatable {
        /// Whether the document should be re-read and re-rendered.
        let reloads: Bool
        /// Whether the watch has to be re-established against the path.
        let reopens: Bool
    }

    /// Decides how to respond to a file-system notification.
    ///
    /// The case that makes this more than a pass-through is the **atomic
    /// save**, which is how most editors write: content goes to a temporary
    /// file that is then renamed over the original. The path the user opened
    /// then refers to a completely new inode, while the watch is still holding
    /// the old, now-unlinked one open — so it would report the first save and
    /// then go permanently silent. A rename or a delete therefore means both
    /// "re-read" *and* "re-open the path", not just one of them.
    static func reaction(to change: Change) -> Reaction {
        Reaction(
            reloads: !change.isDisjoint(with: .replacements) || !change.isDisjoint(with: .edits),
            reopens: !change.isDisjoint(with: .replacements)
        )
    }

    /// How many times re-opening the path is retried before the watch is given
    /// up on.
    ///
    /// A rename is atomic, so the path is usually there on the first attempt.
    /// Editors that unlink before writing (and `rm` followed by a fresh write)
    /// leave a gap, so a bounded retry keeps live-reload working across them.
    /// Bounded because a file that is simply gone must not leave a timer
    /// running for the life of the window: `attempts × delay` is the whole
    /// budget, after which the document keeps showing what it last read.
    static let reopenAttempts = 10

    /// How long to wait between re-open attempts. See ``reopenAttempts``.
    static let reopenRetryDelay: Duration = .milliseconds(20)
}

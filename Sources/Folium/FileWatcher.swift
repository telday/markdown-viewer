import Foundation

/// Watches one file for changes made outside Folium (issue #7).
///
/// The watch is a `DispatchSource` file-system source over an `O_EVTONLY`
/// descriptor — the kernel tells us when the file changes, so nothing polls and
/// an idle window costs nothing. `LiveReload` owns the decisions; this type is
/// the descriptor bookkeeping that carries them out, in particular the re-open
/// dance an atomic save forces (see ``LiveReload/reaction(to:)``).
///
/// Everything here is Dispatch and POSIX, with no SwiftUI/AppKit/WebKit
/// dependency, so it stays in the unit-tested logic layer rather than joining
/// the coverage-excluded glue: the failure mode this guards against — the
/// watch surviving exactly one save and then going quiet forever — is precisely
/// the kind that an untested file would ship with.
///
/// `@unchecked Sendable`: the mutable state is the current source and the
/// cancelled flag, both guarded by `lock`, which the compiler can't verify.
final class FileWatcher: @unchecked Sendable {
    private let url: URL
    private let queue: DispatchQueue
    private let reopenRetryDelay: Duration
    private let reopenAttempts: Int
    private let onChange: @Sendable () -> Void

    private let lock = NSLock()
    private var source: (any DispatchSourceFileSystemObject)?
    private var isCancelled = false

    /// - Parameters:
    ///   - url: the file to watch.
    ///   - queue: the queue notifications are delivered on. Deliberately not
    ///     the main queue: callers hop to whatever isolation they need, and a
    ///     private queue keeps a burst of file-system events off the main
    ///     thread, which is busy painting the document.
    ///   - onChange: called once per notification that means the file's bytes
    ///     changed. Callers are expected to coalesce — see `ReloadCoalescer`.
    init(
        url: URL,
        queue: DispatchQueue = FileWatcher.makeQueue(),
        reopenRetryDelay: Duration = LiveReload.reopenRetryDelay,
        reopenAttempts: Int = LiveReload.reopenAttempts,
        onChange: @escaping @Sendable () -> Void
    ) {
        self.url = url
        self.queue = queue
        self.reopenRetryDelay = reopenRetryDelay
        self.reopenAttempts = reopenAttempts
        self.onChange = onChange
    }

    deinit {
        cancel()
    }

    static func makeQueue() -> DispatchQueue {
        DispatchQueue(label: "com.telday.Folium.FileWatcher", qos: .userInitiated)
    }

    /// Begins watching.
    ///
    /// - Returns: `false` if the file could not be opened — a path that has
    ///   gone away, or one Folium has no permission to read. Live-reload is an
    ///   enhancement to a document that is already on screen, so a caller's
    ///   reasonable response is to carry on without it rather than to fail the
    ///   open.
    @discardableResult
    func start() -> Bool {
        arm()
    }

    /// Stops watching and closes the descriptor. Idempotent, and implied by
    /// deallocation.
    func cancel() {
        var current: (any DispatchSourceFileSystemObject)?
        lock.withLock {
            isCancelled = true
            current = source
            source = nil
        }
        current?.cancel()
    }

    @discardableResult
    private func arm() -> Bool {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return false }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .rename, .delete, .revoke],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.handle(LiveReload.Change(source.data))
        }
        // The descriptor's lifetime is the source's, so it is closed here and
        // nowhere else: a re-arm cancels the old source, and only once that
        // cancellation has drained its in-flight events does the old
        // descriptor go away.
        source.setCancelHandler { close(descriptor) }

        var previous: (any DispatchSourceFileSystemObject)?
        let accepted = lock.withLock {
            guard !isCancelled else { return false }
            previous = self.source
            self.source = source
            return true
        }
        // libdispatch traps on the release of a source that was never resumed,
        // so an unwanted source still has to be started; resuming one that is
        // already cancelled just runs the cancel handler that closes the
        // descriptor.
        guard accepted else { source.cancel(); source.resume(); return false }

        previous?.cancel()
        source.resume()
        return true
    }

    private func handle(_ change: LiveReload.Change) {
        let reaction = LiveReload.reaction(to: change)
        // Re-open first: the reload that follows reads the path, and by then
        // the watch should already be pointed at whatever the path now names.
        if reaction.reopens { reopen(attemptsRemaining: reopenAttempts) }
        if reaction.reloads { onChange() }
    }

    /// Re-establishes the watch against the path after the descriptor stopped
    /// referring to it, retrying while an editor's save is mid-flight.
    ///
    /// Running out of attempts cancels the watch outright rather than leaving
    /// it armed: the descriptor it still holds refers to an unlinked inode
    /// nothing will ever write to again, so keeping it open buys nothing and
    /// costs a file descriptor for the life of the window.
    private func reopen(attemptsRemaining: Int) {
        guard !isCancelledNow else { return }
        if arm() { return }
        guard attemptsRemaining > 0 else { cancel(); return }
        queue.asyncAfter(deadline: .now() + reopenRetryInterval) { [weak self] in
            self?.reopen(attemptsRemaining: attemptsRemaining - 1)
        }
    }

    private var isCancelledNow: Bool {
        lock.withLock { isCancelled }
    }

    /// Dispatch predates `Duration` and `asyncAfter` still speaks
    /// `DispatchTimeInterval`, so the policy's value is converted here rather
    /// than stated twice in two vocabularies.
    private var reopenRetryInterval: DispatchTimeInterval {
        let (seconds, attoseconds) = reopenRetryDelay.components
        return .nanoseconds(Int(seconds * 1_000_000_000 + attoseconds / 1_000_000_000))
    }
}

extension LiveReload.Change {
    /// Mirrors Dispatch's event flags into the logic layer's Dispatch-free
    /// vocabulary, the same way `DocumentTabbing.UserPreference` mirrors
    /// AppKit's tabbing preference.
    init(_ event: DispatchSource.FileSystemEvent) {
        var change: LiveReload.Change = []
        if event.contains(.write) { change.insert(.written) }
        if event.contains(.extend) { change.insert(.extended) }
        if event.contains(.rename) { change.insert(.renamed) }
        if event.contains(.delete) { change.insert(.deleted) }
        if event.contains(.revoke) { change.insert(.revoked) }
        self = change
    }
}

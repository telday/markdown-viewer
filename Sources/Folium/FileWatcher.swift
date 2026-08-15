import Foundation

/// Watches one file for changes made outside Folium (issue #7).
///
/// The kernel pushes notifications to us (via a Dispatch file-system source on
/// an open descriptor), so nothing polls and an idle document costs nothing.
/// `LiveReload` decides what each notification means; this type keeps the
/// descriptor pointed at the right file, which an atomic save makes harder than
/// it sounds — see ``LiveReload/reaction(to:)``.
///
/// `@unchecked Sendable`: `lock` guards the mutable state, which the compiler
/// can't verify.
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
    ///   - queue: where notifications are delivered. Not the main queue: it is
    ///     busy painting the document, and callers can hop from here if they
    ///     need to.
    ///   - onChange: called once per notification. Bursty by nature; callers
    ///     are expected to coalesce (see `ReloadCoalescer`).
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
    /// - Returns: `false` if the file could not be opened (gone, or
    ///   unreadable). The document is already on screen by this point, so the
    ///   sensible response is to carry on without live-reload.
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
        // Closed here and nowhere else. Cancelling a source runs this only
        // after its in-flight events have drained, so re-arming can't pull the
        // descriptor out from under a handler that is still running.
        source.setCancelHandler { close(descriptor) }

        var previous: (any DispatchSourceFileSystemObject)?
        let accepted = lock.withLock {
            guard !isCancelled else { return false }
            previous = self.source
            self.source = source
            return true
        }
        // Dispatch crashes if a source is released without ever being
        // resumed, so even an unwanted one has to be started. Resuming an
        // already-cancelled source just runs the cancel handler.
        guard accepted else { source.cancel(); source.resume(); return false }

        previous?.cancel()
        source.resume()
        return true
    }

    private func handle(_ change: LiveReload.Change) {
        let reaction = LiveReload.reaction(to: change)
        // Re-open first, so the watch is pointed at the current file before
        // the reload reads it.
        if reaction.reopens { reopen(attemptsRemaining: reopenAttempts) }
        if reaction.reloads { onChange() }
    }

    /// Re-points the watch at the path, retrying while a save is mid-flight.
    ///
    /// Running out of attempts cancels the watch: the descriptor it holds
    /// refers to a file nothing will ever write to again, so keeping it open
    /// costs a descriptor for the life of the window and buys nothing.
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

    /// Dispatch predates `Duration`, so the policy's value is converted here
    /// rather than stated twice in two units.
    private var reopenRetryInterval: DispatchTimeInterval {
        let (seconds, attoseconds) = reopenRetryDelay.components
        return .nanoseconds(Int(seconds * 1_000_000_000 + attoseconds / 1_000_000_000))
    }
}

extension LiveReload.Change {
    /// Mirrors Dispatch's flags into `LiveReload`'s own vocabulary, the same
    /// way `DocumentTabbing.UserPreference` mirrors AppKit's tabbing setting.
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

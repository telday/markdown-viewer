/// Runs deferred work after a delay. The seam that lets `ReloadCoalescer`'s
/// timing be driven directly by a test instead of slept through — see
/// `docs/agents/testing.md` on keeping logic in units that can be exercised
/// deterministically.
protocol ReloadScheduler: Sendable {
    @MainActor func schedule(after delay: Duration, run body: @escaping @MainActor () -> Void)
}

/// The real clock. `tolerance: .zero` because the window is half of
/// `CONTEXT.md`'s 100 ms repaint budget and must not be allowed to drift into
/// the other half.
struct SleepingReloadScheduler: ReloadScheduler {
    @MainActor
    func schedule(after delay: Duration, run body: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: delay, tolerance: .zero)
            body()
        }
    }
}

/// Collapses a burst of file-change notifications into a single reload
/// (issue #7).
///
/// A single ⌘S is several file-system events, and an editor's autosave or a
/// running formatter produces a stream of them; re-reading and re-rendering on
/// each one would be a reload storm.
///
/// The window runs from the **first** notification in a burst, not the last.
/// Resetting it on every notification — the more familiar debounce — would let
/// a file that is written continuously (a log tailing in, a generator emitting
/// incrementally) starve the reload indefinitely, and would push the ordinary
/// single-save case past the 100 ms repaint budget as soon as a save produced
/// two events. This shape instead guarantees a reload no later than one window
/// after the change that opened it, and no more than one reload per window.
@MainActor
final class ReloadCoalescer {
    private let window: Duration
    private let scheduler: any ReloadScheduler
    private let reload: @MainActor () -> Void
    private var isWaiting = false

    init(
        window: Duration = LiveReload.coalescingWindow,
        scheduler: any ReloadScheduler = SleepingReloadScheduler(),
        reload: @escaping @MainActor () -> Void
    ) {
        self.window = window
        self.scheduler = scheduler
        self.reload = reload
    }

    /// Call for every file-change notification. The first one in a burst opens
    /// the window; the rest are absorbed by it.
    func noteChange() {
        guard !isWaiting else { return }
        isWaiting = true
        scheduler.schedule(after: window) { [weak self] in
            guard let self else { return }
            // Cleared *before* reloading, so a write that lands while the file
            // is being re-read opens a fresh window rather than being
            // swallowed by the one that is closing.
            isWaiting = false
            reload()
        }
    }
}

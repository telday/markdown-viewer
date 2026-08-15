/// Runs work after a delay. Injected into `ReloadCoalescer` so tests can drive
/// the timing directly instead of sleeping through it.
protocol ReloadScheduler: Sendable {
    @MainActor func schedule(after delay: Duration, run body: @escaping @MainActor () -> Void)
}

/// The real clock. `tolerance: .zero` because the window is already half of
/// the 100 ms repaint budget and mustn't be allowed to drift into the rest.
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
/// One save is several file-system events, and an autosave or a formatter
/// produces a stream of them. Reloading on each would be a storm.
///
/// The window runs from the **first** notification in a burst, not the last.
/// The more familiar debounce — restarting the timer on every notification —
/// would let a continuously written file starve the reload forever, and would
/// blow the 100 ms repaint budget as soon as a save produced two events. This
/// way there is at most one reload per window, and never more than one window
/// between a change and its reload.
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
            // Cleared *before* reloading, so a write that lands mid-read
            // opens a fresh window instead of being swallowed by this one.
            isWaiting = false
            reload()
        }
    }
}

import Foundation

/// Instrumentation for the latency budgets in `CONTEXT.md`. Emits a
/// timestamped marker line to stderr, but only when the FOLIUM_BENCH
/// environment variable is set — a release user must never see this.
///
/// A marker carries a wall-clock timestamp (seconds since the Unix epoch),
/// not a duration. A duration measured entirely inside this process cannot
/// see process spawn, dyld linking, or AppKit start-up — the part of cold
/// launch a user actually feels happens before any of our code runs.
/// `scripts/bench.sh` takes its own wall-clock reading immediately before it
/// execs the app, so subtracting that reading from a marker's timestamp
/// yields a duration that includes launch itself. Both readings come from
/// the same clock (`Date`'s epoch, matched in the script by Python's
/// `time.time()`), which is what makes the subtraction valid across the two
/// processes.
struct BenchMarker: Sendable {
    /// Injected so tests can supply a fixed timestamp instead of the real
    /// wall clock.
    private let now: @Sendable () -> Double

    /// Injected lookup of FOLIUM_BENCH so tests can simulate it being set or
    /// unset without touching the real environment.
    private let getenv: @Sendable (String) -> String?

    /// Injected so tests can capture what would have gone to stderr instead
    /// of writing to the real file descriptor.
    private let write: @Sendable (Data) -> Void

    init(
        now: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 },
        getenv: @escaping @Sendable (String) -> String? = {
            guard let cString = Foundation.getenv($0) else { return nil }
            return String(cString: cString)
        },
        write: @escaping @Sendable (Data) -> Void = { FileHandle.standardError.write($0) }
    ) {
        self.now = now
        self.getenv = getenv
        self.write = write
    }

    /// Emit a marker line if FOLIUM_BENCH is set. A complete no-op
    /// otherwise: no clock read, no formatting, nothing written.
    ///
    /// Deliberately stateless — there is no "first call" special case and
    /// no shared mutable state, so calling this from several places
    /// concurrently is never a data race, and unit tests can call it in any
    /// order without one leaking into another.
    func mark(_ event: String) {
        guard getenv("FOLIUM_BENCH") != nil else { return }
        guard let data = Self.formatMarkerLine(event: event, timestamp: now()).data(using: .utf8) else { return }
        write(data)
    }

    /// Formats one marker line. Pure, and kept separate from `mark` so the
    /// wire format can be unit-tested without an environment or a clock.
    static func formatMarkerLine(event: String, timestamp: Double) -> String {
        "FOLIUM_BENCH \(event) \(String(format: "%.6f", timestamp))\n"
    }
}

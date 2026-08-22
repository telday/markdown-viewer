import Foundation

/// Instrumentation for latency budgets. Emits timestamped markers to stderr
/// only when FOLIUM_BENCH is set, allowing measurement of key moments in the
/// app's lifecycle without imposing overhead on normal users.
///
/// When the env var is unset, operations are complete no-ops: no allocation,
/// no formatting, nothing on stderr.
struct BenchMarker: Sendable {
    /// Returns the current time in monotonic seconds since an arbitrary epoch.
    /// Injected for testability; allows tests to provide a fixed clock.
    var clock: @Sendable () -> Double

    /// Injected lookup of the FOLIUM_BENCH environment variable; allows tests
    /// to simulate it being set or unset.
    var getenv: @Sendable (String) -> String?

    init(
        clock: @escaping @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime },
        getenv: @escaping @Sendable (String) -> String? = {
            guard let cStr = Foundation.getenv($0) else { return nil }
            return String(cString: cStr)
        }
    ) {
        self.clock = clock
        self.getenv = getenv
    }

    /// Emit a marker to stderr if FOLIUM_BENCH is set.
    ///
    /// The marker is formatted as "FOLIUM_BENCH <event> <monotonic-seconds>",
    /// for easy parsing by the orchestration script. When FOLIUM_BENCH is unset,
    /// this is a complete no-op.
    func mark(_ event: String) {
        guard getenv("FOLIUM_BENCH") != nil else { return }
        let elapsed = clock()
        let line = "FOLIUM_BENCH \(event) \(String(format: "%.3f", elapsed))\n"
        if let data = line.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }
}

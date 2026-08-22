import Foundation
import Testing
@testable import Folium

/// Unit tests for `BenchMarker`. `write` and `now` are injected so these can
/// assert on the exact bytes that would go to stderr, rather than the
/// `#expect(true)` placeholders a real `FileHandle` would have forced.
struct BenchMarkerTests {
    @Test func isACompleteNoOpWhenBenchEnvIsUnset() {
        let sink = RecordingSink()
        let clockReads = Counter()
        let marker = BenchMarker(
            now: { clockReads.increment(); return 1.0 },
            getenv: { _ in nil },
            write: sink.record
        )

        marker.mark("first-paint")

        #expect(sink.writes.isEmpty)
        // No clock read either: an event that never gets written shouldn't
        // even pay for a timestamp.
        #expect(clockReads.total == 0)
    }

    @Test func writesAFormattedLineWhenBenchEnvIsSet() {
        let sink = RecordingSink()
        let marker = BenchMarker(
            now: { 1_700_000_000.123456 },
            getenv: { $0 == "FOLIUM_BENCH" ? "1" : nil },
            write: sink.record
        )

        marker.mark("first-paint")

        #expect(sink.writes.count == 1)
        let line = String(data: sink.writes[0], encoding: .utf8)
        #expect(line == "FOLIUM_BENCH first-paint 1700000000.123456\n")
    }

    @Test func looksUpExactlyTheFoliumBenchKey() {
        let lookups = StringLog()
        let marker = BenchMarker(
            now: { 0 },
            getenv: { lookups.record($0); return nil },
            write: { _ in }
        )

        marker.mark("render-start")

        #expect(lookups.entries == ["FOLIUM_BENCH"])
    }

    @Test func hasNoSharedStateAcrossCalls() {
        // BenchMarker used to latch a "launch already emitted" flag in a
        // global. Rewritten to be stateless, so calling it many times, in
        // any order, writes one line per call — nothing carries over.
        let sink = RecordingSink()
        let marker = BenchMarker(
            now: { 5.0 },
            getenv: { $0 == "FOLIUM_BENCH" ? "1" : nil },
            write: sink.record
        )

        marker.mark("render-start")
        marker.mark("render-start")
        marker.mark("render-end")

        #expect(sink.writes.count == 3)
    }

    @Test func formatMarkerLineEmbedsTheEventNameAndSixDecimalTimestamp() {
        let line = BenchMarker.formatMarkerLine(event: "reload-paint", timestamp: 12.5)

        #expect(line == "FOLIUM_BENCH reload-paint 12.500000\n")
    }
}

/// Captures what a `BenchMarker` would have written, without touching the
/// real file descriptor. `@unchecked Sendable`: a stored `@Sendable`
/// property on `BenchMarker` needs a Sendable closure, and this test double
/// is only ever touched from one thread within a single test.
private final class RecordingSink: @unchecked Sendable {
    private(set) var writes: [Data] = []

    func record(_ data: Data) {
        writes.append(data)
    }
}

/// Records the strings a `getenv` stub was asked to look up. Same
/// `@unchecked Sendable` rationale as `RecordingSink`.
private final class StringLog: @unchecked Sendable {
    private(set) var entries: [String] = []

    func record(_ value: String) {
        entries.append(value)
    }
}

/// A plain call counter. Same `@unchecked Sendable` rationale as
/// `RecordingSink`.
private final class Counter: @unchecked Sendable {
    private(set) var total = 0

    func increment() {
        total += 1
    }
}

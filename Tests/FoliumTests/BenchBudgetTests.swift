import Foundation
import Testing
@testable import Folium

/// Unit tests for benchmark budgets and reporting.
struct BenchBudgetTests {
    @Test func budgetLookupReturnsCorrectValues() {
        #expect(BenchBudget.budget(for: "cold-launch") == 500)
        #expect(BenchBudget.budget(for: "reload-paint") == 100)
        #expect(BenchBudget.budget(for: "render") == nil)
        #expect(BenchBudget.budget(for: "unknown") == nil)
    }

    @Test func reportLineShowsUnderBudgetAsSuccess() {
        let line = BenchBudget.reportLine(event: "cold-launch", measuredMs: 250)
        #expect(line.contains("250 ms"))
        #expect(line.contains("✓"))
        #expect(line.contains("Cold launch"))
        #expect(!line.contains("over by"))
    }

    @Test func reportLineShowsAtBudgetAsSuccess() {
        let line = BenchBudget.reportLine(event: "cold-launch", measuredMs: 500)
        #expect(line.contains("500 ms"))
        #expect(line.contains("✓"))
    }

    @Test func reportLineShowsOverBudgetAsFailure() {
        let line = BenchBudget.reportLine(event: "reload-paint", measuredMs: 120)
        #expect(line.contains("120 ms"))
        #expect(line.contains("✗"))
        #expect(line.contains("over by 20 ms"))
    }

    @Test func reportLineShowsDashForUnbudgetedEvents() {
        let line = BenchBudget.reportLine(event: "render", measuredMs: 150)
        #expect(line.contains("150 ms"))
        #expect(line.contains("–"))
    }

    @Test func reportLineForUnmeasuredIncludesReason() {
        let reason = "requires driving an already-running app's UI"
        let line = BenchBudget.reportLineUnmeasured(event: "warm-open", reason: reason)
        #expect(line.contains("not measured"))
        #expect(line.contains(reason))
    }

    @Test func reportLinesAlignProperlyWithDots() {
        let line = BenchBudget.reportLine(event: "cold-launch", measuredMs: 250)
        // The line should have dots between the event name and the measurement.
        #expect(line.contains("..."))
    }

    @Test func budgetTableLinesCoverEveryBudgetedEvent() {
        let lines = BenchBudget.budgetTableLines()
        #expect(lines.contains("FOLIUM_BENCH_BUDGET cold-launch 500"))
        #expect(lines.contains("FOLIUM_BENCH_BUDGET reload-paint 100"))
        // "render" has no budget, so it must not appear here — scripts/bench.sh
        // treats an event with no budget line as unbudgeted, informational only.
        #expect(!lines.contains { $0.contains("render") })
    }

    @Test func unmeasuredReportLinesCoverEveryPermanentlyUnmeasuredMoment() {
        let lines = BenchBudget.unmeasuredReportLines()
        #expect(lines.count == 3)
        // Event-prefixed, like BenchMarker.measure's FOLIUM_BENCH_REPORT
        // lines, so scripts/bench.sh can look either kind up by event.
        #expect(lines.contains { $0.hasPrefix("FOLIUM_BENCH_REPORT warm-open ") && $0.contains("Warm open") })
        #expect(lines.contains { $0.hasPrefix("FOLIUM_BENCH_REPORT tab-switch ") && $0.contains("Tab switch") })
        #expect(lines.contains { $0.hasPrefix("FOLIUM_BENCH_REPORT scrolling ") && $0.contains("Scrolling") })
        #expect(lines.allSatisfy { $0.contains("not measured") })
    }
}

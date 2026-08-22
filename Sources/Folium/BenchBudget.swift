import Foundation

/// Budget thresholds and reporting for latency measurements.
struct BenchBudget {
    /// The budget for each moment, in milliseconds. Only moments with a budget
    /// are enforced; others are measured but not gated.
    static let budgets: [String: Double] = [
        "launch": 500,           // Cold launch → first document painted
        "reload-paint": 100      // Live-reload: file written → repainted
        // "render" has no budget — it's informational
    ]

    /// The formatted name for each moment, for human-readable reports.
    static let names: [String: String] = [
        "launch": "Cold launch → first document painted",
        "reload-paint": "Live-reload: file written → repainted",
        "render": "Markdown → HTML render (fixture)"
    ]

    /// Lookup the budget for an event in milliseconds, or nil if unmeasured.
    static func budget(for event: String) -> Double? {
        return budgets[event]
    }

    /// Format a measurement line for the report, comparing measured vs budget.
    ///
    /// Returns a line like "  Cold launch....... 245 ms  ✓" or
    /// "  Cold launch....... 520 ms  ✗ (over by 20 ms)".
    static func reportLine(event: String, measuredMs: Double) -> String {
        let name = names[event] ?? event
        let status: String
        var suffix = ""

        if let budgetMs = budget(for: event) {
            if measuredMs <= budgetMs {
                status = "✓"
            } else {
                let overMs = measuredMs - budgetMs
                status = "✗"
                suffix = " (over by \(Int(overMs)) ms)"
            }
        } else {
            status = "–"
        }

        // Pad to align the status column.
        let dots = max(1, 60 - name.count - String(format: "%.0f", measuredMs).count)
        let padding = String(repeating: ".", count: dots)
        return "  \(name)\(padding) \(Int(measuredMs)) ms  \(status)\(suffix)"
    }

    /// Format a line for an unmeasured moment.
    static func reportLineUnmeasured(event: String, reason: String) -> String {
        let name = names[event] ?? event
        let dots = max(1, 60 - name.count - 12) // "not measured" is ~12 chars
        let padding = String(repeating: ".", count: dots)
        return "  \(name)\(padding) not measured (\(reason))"
    }
}

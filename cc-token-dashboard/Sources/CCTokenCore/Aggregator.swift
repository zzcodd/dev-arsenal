import Foundation

public enum Aggregator {
    /// Drop duplicate lines. Records with no dedupe key are always kept.
    public static func dedupe(_ records: [UsageRecord]) -> [UsageRecord] {
        var seen = Set<String>()
        var out: [UsageRecord] = []
        out.reserveCapacity(records.count)
        for r in records {
            if let key = r.dedupeKey {
                if seen.contains(key) { continue }
                seen.insert(key)
            }
            out.append(r)
        }
        return out
    }

    /// Filter `records` to `range` and roll them up into everything the UI shows.
    /// Day boundaries use `calendar` (local timezone by default).
    public static func aggregate(_ records: [UsageRecord],
                                 range: TimeRange,
                                 calendar: Calendar = .current,
                                 now: Date = Date()) -> AggregatedUsage {
        let todayStart = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
        let fiveHoursAgo = now.addingTimeInterval(-5 * 3600)

        var agg = AggregatedUsage()
        var projectTotals: [String: Int] = [:]
        var modelTotals: [String: Int] = [:]
        var sourceTotals: [String: Int] = [:]
        var dayTotals: [Date: Int] = [:]

        for r in records {
            // Rolling 5h window is independent of the selected range.
            if r.timestamp >= fiveHoursAgo { agg.last5hTokens += r.total }

            switch range {
            case .today: if r.timestamp < todayStart { continue }
            case .week:  if r.timestamp < weekStart { continue }
            case .all:   break
            }

            agg.totalTokens += r.total
            agg.input += r.input
            agg.cacheCreation += r.cacheCreation
            agg.cacheRead += r.cacheRead
            agg.output += r.output
            agg.estimatedCostUSD += PricingTable.cost(for: r)

            projectTotals[r.project, default: 0] += r.total
            modelTotals[shortModelName(r.model), default: 0] += r.total
            sourceTotals[r.source, default: 0] += r.total
            let day = calendar.startOfDay(for: r.timestamp)
            dayTotals[day, default: 0] += r.total
        }

        agg.byProject = projectTotals
            .filter { $0.value > 0 }
            .map { NamedTotal(name: $0.key, tokens: $0.value) }
            .sorted { $0.tokens > $1.tokens }
        agg.byModel = modelTotals
            .filter { $0.value > 0 }
            .map { NamedTotal(name: $0.key, tokens: $0.value) }
            .sorted { $0.tokens > $1.tokens }
        agg.bySource = sourceTotals
            .filter { $0.value > 0 }
            .map { NamedTotal(name: $0.key, tokens: $0.value) }
            .sorted { $0.tokens > $1.tokens }

        // Trend: last 7 calendar days, oldest first, zero-filled.
        agg.dailyTotals = (0..<7).reversed().compactMap { offset -> DailyTotal? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: todayStart) else { return nil }
            return DailyTotal(date: day, tokens: dayTotals[day] ?? 0)
        }

        return agg
    }

    /// "claude-opus-4-8" → "Opus", "claude-sonnet-4-6" → "Sonnet", etc.
    public static func shortModelName(_ model: String) -> String {
        let m = model.lowercased()
        if m.contains("opus") { return "Opus" }
        if m.contains("sonnet") { return "Sonnet" }
        if m.contains("haiku") { return "Haiku" }
        return model
    }
}

import Testing
import Foundation
@testable import CCTokenCore

private func record(_ ts: Date, project: String = "p", model: String = "claude-opus-4-8",
                    input: Int = 0, cacheCreation: Int = 0, cacheRead: Int = 0, output: Int = 0,
                    source: String = "Claude Code", key: String? = nil) -> UsageRecord {
    UsageRecord(timestamp: ts, project: project, model: model,
                input: input, cacheCreation: cacheCreation, cacheRead: cacheRead, output: output,
                source: source, dedupeKey: key)
}

@Test func parseLineExtractsUsage() {
    let line = """
    {"type":"assistant","cwd":"/Users/x/dev/my-app","timestamp":"2026-06-14T16:35:24.056Z","requestId":"req_1","message":{"id":"msg_1","model":"claude-opus-4-8","usage":{"input_tokens":3288,"cache_creation_input_tokens":4745,"cache_read_input_tokens":15576,"output_tokens":1467}}}
    """
    let rec = JSONLParser.parseLine(line.data(using: .utf8)!, fallbackProject: "fallback")
    #expect(rec != nil)
    #expect(rec?.project == "my-app")          // from cwd, not fallback
    #expect(rec?.input == 3288)
    #expect(rec?.cacheRead == 15576)
    #expect(rec?.total == 3288 + 4745 + 15576 + 1467)
    #expect(rec?.dedupeKey == "msg_1:req_1")
}

@Test func nonAssistantLinesIgnored() {
    let user = #"{"type":"user","message":{"content":"hi"}}"#
    #expect(JSONLParser.parseLine(user.data(using: .utf8)!, fallbackProject: "f") == nil)
    #expect(JSONLParser.parseLine("not json".data(using: .utf8)!, fallbackProject: "f") == nil)
}

@Test func dedupeDropsRepeatedKeys() {
    let now = Date()
    let recs = [record(now, output: 10, key: "a"),
                record(now, output: 10, key: "a"),   // dup
                record(now, output: 5, key: "b"),
                record(now, output: 7, key: nil)]     // no key, always kept
    let deduped = Aggregator.dedupe(recs)
    let outputSum = deduped.reduce(0) { $0 + $1.output }
    #expect(deduped.count == 3)
    #expect(outputSum == 22)
}

@Test func aggregateTodayFiltersByDay() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 12))!
    let yesterday = cal.date(byAdding: .day, value: -1, to: now)!

    let recs = [record(now, output: 100), record(yesterday, output: 999)]
    #expect(Aggregator.aggregate(recs, range: .today, calendar: cal, now: now).totalTokens == 100)
    #expect(Aggregator.aggregate(recs, range: .all, calendar: cal, now: now).totalTokens == 1099)
}

@Test func costUsesModelTable() {
    // 1M Opus input ($15) + 1M output ($75) = $90.
    let r = record(Date(), model: "claude-opus-4-8", input: 1_000_000, output: 1_000_000)
    #expect(abs(PricingTable.cost(for: r) - 90.0) < 0.001)
    // Unknown model → 0.
    #expect(PricingTable.cost(for: record(Date(), model: "mystery", input: 1_000_000)) == 0)
}

@Test func formatTokens() {
    #expect(Format.tokens(940) == "940")
    #expect(Format.tokens(320_000) == "320K")
    #expect(Format.tokens(2_412_033) == "2.4M")
    #expect(Format.tokens(2_000_000) == "2M")
}

@Test func trendHasSevenDays() {
    #expect(Aggregator.aggregate([record(Date(), output: 1)], range: .all).dailyTotals.count == 7)
}

@Test func aggregateBreaksDownBySource() {
    let now = Date()
    let recs = [record(now, output: 100, source: "Claude Code"),
                record(now, output: 40, source: "Codex"),
                record(now, output: 60, source: "Claude Code")]
    let agg = Aggregator.aggregate(recs, range: .all)
    #expect(agg.bySource.count == 2)
    #expect(agg.bySource.first?.name == "Claude Code")   // sorted desc: 160 > 40
    #expect(agg.bySource.first?.tokens == 160)
}

@Test func defaultDataSourceResolvesToClaudeCode() {
    let sources = DataSource.defaults
    #expect(sources.count == 1)
    let resolved = sources[0].resolved()
    #expect(resolved != nil)
    #expect(resolved?.provider.displayName == "Claude Code")
    // Empty path => falls back to the provider default root (…/.claude/projects).
    #expect(resolved?.root.lastPathComponent == "projects")
}

@Test func customFolderSourceNeedsAPath() {
    // A generic-folder source with no path can't resolve (no default location).
    let s = DataSource(id: "x", providerType: GenericClaudeFormatProvider.typeId,
                       name: "Eden", path: "", enabled: true)
    #expect(s.resolved() == nil)
    // With a path it resolves.
    let s2 = DataSource(id: "x", providerType: GenericClaudeFormatProvider.typeId,
                        name: "Eden", path: "/tmp/eden-logs", enabled: true)
    #expect(s2.resolved() != nil)
}

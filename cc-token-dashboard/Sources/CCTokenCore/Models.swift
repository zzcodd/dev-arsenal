import Foundation

/// One assistant message's token usage, parsed from a single JSONL line.
public struct UsageRecord: Sendable, Equatable {
    public let timestamp: Date
    public let project: String          // display name (cwd's last path component)
    /// Which tool/data source produced this (e.g. "Claude Code", "Codex"). The store
    /// stamps it per configured data source; the parser leaves the default.
    public var source: String
    public let model: String            // e.g. "claude-opus-4-8"
    public let input: Int
    public let cacheCreation: Int       // writing cache (~1.25x input price)
    public let cacheRead: Int           // reading cache (~0.1x input price)
    public let output: Int
    /// Stable key used to drop duplicate lines (message.id + requestId). nil = always counted.
    public let dedupeKey: String?

    public init(timestamp: Date, project: String, model: String,
                input: Int, cacheCreation: Int, cacheRead: Int, output: Int,
                source: String = "Claude Code", dedupeKey: String?) {
        self.timestamp = timestamp
        self.project = project
        self.source = source
        self.model = model
        self.input = input
        self.cacheCreation = cacheCreation
        self.cacheRead = cacheRead
        self.output = output
        self.dedupeKey = dedupeKey
    }

    /// All four token buckets summed.
    public var total: Int { input + cacheCreation + cacheRead + output }
}

/// Time window for aggregation. Day boundaries use the local calendar/timezone.
public enum TimeRange: String, CaseIterable, Sendable {
    case today = "Today"
    case week  = "7 Days"
    case all   = "All"
}

/// A named token total (used for per-project and per-model breakdowns).
public struct NamedTotal: Sendable, Equatable, Identifiable {
    public let name: String
    public let tokens: Int
    public var id: String { name }
    public init(name: String, tokens: Int) { self.name = name; self.tokens = tokens }
}

/// One day's total, for the trend chart.
public struct DailyTotal: Sendable, Equatable, Identifiable {
    public let date: Date
    public let tokens: Int
    public var id: Date { date }
    public init(date: Date, tokens: Int) { self.date = date; self.tokens = tokens }
}

/// Fully aggregated usage for a given time range — everything the UI renders.
public struct AggregatedUsage: Sendable, Equatable {
    public var totalTokens: Int = 0
    public var input: Int = 0
    public var cacheCreation: Int = 0
    public var cacheRead: Int = 0
    public var output: Int = 0
    public var estimatedCostUSD: Double = 0
    public var byProject: [NamedTotal] = []   // sorted desc
    public var byModel: [NamedTotal] = []      // sorted desc
    public var bySource: [NamedTotal] = []     // sorted desc (per tool/data source)
    public var dailyTotals: [DailyTotal] = []  // last 7 days, oldest first
    public var last5hTokens: Int = 0           // rolling 5-hour window (informational)

    public init() {}
}

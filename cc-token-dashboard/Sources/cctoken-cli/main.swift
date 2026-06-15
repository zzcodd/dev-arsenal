import Foundation
import CCTokenCore

// M0 verification tool: scan everything, print today's usage so we can sanity-check
// the numbers before wiring them into the menu bar UI.
//
// Usage:
//   cctoken-cli            # today
//   cctoken-cli week
//   cctoken-cli all

let rangeArg = CommandLine.arguments.dropFirst().first?.lowercased() ?? "today"
let range: TimeRange = {
    switch rangeArg {
    case "week", "7days", "7d": return .week
    case "all": return .all
    default: return .today
    }
}()

let transcripts = TranscriptScanner.allTranscripts()
FileHandle.standardError.write("Scanning \(transcripts.count) transcript files…\n".data(using: .utf8)!)

var all: [UsageRecord] = []
for t in transcripts {
    let result = JSONLParser.parse(at: t.url, fallbackProject: t.fallbackProject, fromOffset: 0)
    all.append(contentsOf: result.records)
}

let deduped = Aggregator.dedupe(all)
let agg = Aggregator.aggregate(deduped, range: range)

print("""

  ── CC Token Usage · \(range.rawValue) ──────────────────

  Total      \(Format.grouped(agg.totalTokens)) tokens   ≈ \(Format.cost(agg.estimatedCostUSD))

  Input         \(Format.grouped(agg.input))
  Output        \(Format.grouped(agg.output))
  Cache write   \(Format.grouped(agg.cacheCreation))
  Cache read    \(Format.grouped(agg.cacheRead))

  Last 5h       \(Format.grouped(agg.last5hTokens)) tokens
""")

if !agg.byModel.isEmpty {
    print("\n  By model:")
    for m in agg.byModel {
        print("    \(m.name.padding(toLength: 10, withPad: " ", startingAt: 0)) \(Format.grouped(m.tokens))")
    }
}

if !agg.byProject.isEmpty {
    print("\n  By project (top 10):")
    for p in agg.byProject.prefix(10) {
        let pct = agg.totalTokens > 0 ? Double(p.tokens) / Double(agg.totalTokens) * 100 : 0
        let name = p.name.padding(toLength: 24, withPad: " ", startingAt: 0)
        print("    \(name) \(Format.grouped(p.tokens))  (\(String(format: "%.0f", pct))%)")
    }
}

print("")
print("  Records: \(all.count) parsed, \(deduped.count) after dedupe")
print("")

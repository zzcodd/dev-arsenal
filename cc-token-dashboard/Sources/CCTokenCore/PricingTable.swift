import Foundation

/// USD per 1,000,000 tokens for one model, split by token bucket.
public struct ModelPricing: Sendable {
    public let inputPerM: Double
    public let outputPerM: Double
    public let cacheWritePerM: Double
    public let cacheReadPerM: Double
}

/// Static model → price table. Used only to show an *equivalent market value* —
/// on a subscription this is NOT your actual bill.
///
/// TODO: verify against current official pricing before trusting the $ numbers.
/// Cache write ≈ 1.25× input, cache read ≈ 0.1× input (Anthropic's documented ratios).
public enum PricingTable {
    static let table: [(prefix: String, pricing: ModelPricing)] = [
        ("opus",   ModelPricing(inputPerM: 15.0, outputPerM: 75.0, cacheWritePerM: 18.75, cacheReadPerM: 1.50)),
        ("sonnet", ModelPricing(inputPerM: 3.0,  outputPerM: 15.0, cacheWritePerM: 3.75,  cacheReadPerM: 0.30)),
        ("haiku",  ModelPricing(inputPerM: 0.80, outputPerM: 4.0,  cacheWritePerM: 1.00,  cacheReadPerM: 0.08)),
    ]

    public static func pricing(for model: String) -> ModelPricing? {
        let m = model.lowercased()
        return table.first { m.contains($0.prefix) }?.pricing
    }

    /// Estimated USD cost for a single record. Unknown models cost 0.
    public static func cost(for r: UsageRecord) -> Double {
        guard let p = pricing(for: r.model) else { return 0 }
        return Double(r.input)         / 1_000_000 * p.inputPerM
             + Double(r.output)        / 1_000_000 * p.outputPerM
             + Double(r.cacheCreation) / 1_000_000 * p.cacheWritePerM
             + Double(r.cacheRead)     / 1_000_000 * p.cacheReadPerM
    }
}

import Foundation

public enum Format {
    /// 2_412_033 → "2.4M", 320_000 → "320K", 940 → "940".
    public static func tokens(_ n: Int) -> String {
        let v = Double(n)
        if v >= 1_000_000 {
            return trimmed(v / 1_000_000) + "M"
        } else if v >= 1_000 {
            return trimmed(v / 1_000) + "K"
        }
        return "\(n)"
    }

    /// Grouped full number: 2412033 → "2,412,033".
    public static func grouped(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    public static func cost(_ usd: Double) -> String {
        String(format: "$%.2f", usd)
    }

    private static func trimmed(_ v: Double) -> String {
        // One decimal, but drop a trailing ".0": 2.0 → "2", 2.4 → "2.4".
        let s = String(format: "%.1f", v)
        return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
    }
}

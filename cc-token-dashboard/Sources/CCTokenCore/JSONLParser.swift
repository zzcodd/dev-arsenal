import Foundation

/// Result of an incremental parse: new records plus the byte offset to resume from.
public struct ParseResult: Sendable {
    public var records: [UsageRecord]
    public var newOffset: UInt64
    public init(records: [UsageRecord], newOffset: UInt64) {
        self.records = records
        self.newOffset = newOffset
    }
}

public enum JSONLParser {
    private static let newline: UInt8 = 0x0A

    /// Two ISO8601 parsers — CC timestamps usually carry fractional seconds, but be lenient.
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseDate(_ s: String) -> Date? {
        isoFractional.date(from: s) ?? isoPlain.date(from: s)
    }

    /// Incrementally read a JSONL file from `offset`, parsing each complete line with the
    /// supplied per-line parser. This is the generic, provider-agnostic byte reader: only
    /// the line→record mapping differs between tools, so providers pass their own `lineParser`.
    ///
    /// Only fully-terminated lines (ending in `\n`) are consumed; a trailing partial line is
    /// left for the next call. If the file shrank below `offset` (rotation/truncation) we
    /// restart from 0.
    public static func read(at url: URL,
                            fromOffset offset: UInt64,
                            lineParser: (Data) -> UsageRecord?) -> ParseResult {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return ParseResult(records: [], newOffset: offset)
        }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        var start = offset
        if size < offset { start = 0 }           // file was rotated/truncated
        if size == start { return ParseResult(records: [], newOffset: start) }

        do { try handle.seek(toOffset: start) } catch {
            return ParseResult(records: [], newOffset: offset)
        }
        let data = handle.readDataToEndOfFile()

        guard let lastNewline = data.lastIndex(of: newline) else {
            return ParseResult(records: [], newOffset: start)   // no complete line yet
        }
        let complete = data[...lastNewline]                     // includes the final \n
        let newOffset = start + UInt64(complete.count)

        var records: [UsageRecord] = []
        for line in complete.split(separator: newline, omittingEmptySubsequences: true) {
            if let rec = lineParser(Data(line)) {
                records.append(rec)
            }
        }
        return ParseResult(records: records, newOffset: newOffset)
    }

    /// Convenience for the Claude Code format (used by the CLI and ClaudeCodeProvider).
    public static func parse(at url: URL, fallbackProject: String, fromOffset offset: UInt64) -> ParseResult {
        read(at: url, fromOffset: offset) { parseLine($0, fallbackProject: fallbackProject) }
    }

    /// Parse one Claude Code JSONL line into a UsageRecord, or nil if it isn't a billable
    /// assistant turn.
    public static func parseLine(_ data: Data, fallbackProject: String) -> UsageRecord? {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (obj["type"] as? String) == "assistant",
              let message = obj["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any]
        else { return nil }

        let model = (message["model"] as? String) ?? "unknown"

        let project: String
        if let cwd = obj["cwd"] as? String, !cwd.isEmpty {
            project = (cwd as NSString).lastPathComponent
        } else {
            project = fallbackProject
        }

        let timestamp = (obj["timestamp"] as? String).flatMap(parseDate) ?? Date(timeIntervalSince1970: 0)

        func intVal(_ key: String) -> Int {
            // JSON numbers may decode as Int or Double; handle both.
            if let i = usage[key] as? Int { return i }
            if let d = usage[key] as? Double { return Int(d) }
            return 0
        }

        var dedupeKey: String? = nil
        if let id = message["id"] as? String {
            dedupeKey = id + ":" + ((obj["requestId"] as? String) ?? "")
        }

        return UsageRecord(
            timestamp: timestamp,
            project: project,
            model: model,
            input: intVal("input_tokens"),
            cacheCreation: intVal("cache_creation_input_tokens"),
            cacheRead: intVal("cache_read_input_tokens"),
            output: intVal("output_tokens"),
            dedupeKey: dedupeKey
        )
    }
}

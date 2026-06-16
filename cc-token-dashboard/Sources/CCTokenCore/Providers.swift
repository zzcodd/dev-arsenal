import Foundation

/// One transcript file plus the project name to fall back to when a line lacks its own.
public struct TranscriptFile: Sendable {
    public let url: URL
    public let fallbackProject: String
    public init(url: URL, fallbackProject: String) {
        self.url = url
        self.fallbackProject = fallbackProject
    }
}

/// A source of token-usage data. Each provider knows only two things: where its logs live
/// and how to turn one log line into a `UsageRecord`. Everything downstream (aggregation,
/// UI) is provider-agnostic, so adding a tool = adding a provider.
public protocol UsageProvider: Sendable {
    /// Stable identifier persisted in the user's config.
    static var typeId: String { get }
    /// Human-readable name (also stamped onto records as their `source`).
    var displayName: String { get }
    /// Default location for this tool's logs, or nil if it must be pointed manually.
    func defaultRoot() -> URL?
    func transcripts(root: URL) -> [TranscriptFile]
    func parseLine(_ data: Data, fallbackProject: String) -> UsageRecord?
}

/// Claude Code itself: the fixed `~/.claude/projects` layout.
public struct ClaudeCodeProvider: UsageProvider {
    public static let typeId = "claude-code"
    public let displayName: String
    public init(displayName: String = "Claude Code") { self.displayName = displayName }

    public func defaultRoot() -> URL? { TranscriptScanner.rootURL }

    public func transcripts(root: URL) -> [TranscriptFile] {
        TranscriptScanner.allTranscripts(root: root)
            .map { TranscriptFile(url: $0.url, fallbackProject: $0.fallbackProject) }
    }

    public func parseLine(_ data: Data, fallbackProject: String) -> UsageRecord? {
        JSONLParser.parseLine(data, fallbackProject: fallbackProject)
    }
}

/// A user-pointed directory of Claude-Code-format JSONL files — e.g. an internal wrapper
/// (like "Eden") that delegates to Claude Code and writes the same schema, but in a
/// different/unknown location. Same parser, no default root, recursive scan.
public struct GenericClaudeFormatProvider: UsageProvider {
    public static let typeId = "claude-format-generic"
    public let displayName: String
    public init(displayName: String) { self.displayName = displayName }

    public func defaultRoot() -> URL? { nil }

    public func transcripts(root: URL) -> [TranscriptFile] {
        TranscriptScanner.jsonlFilesRecursive(under: root)
            .map { TranscriptFile(url: $0.url, fallbackProject: $0.fallbackProject) }
    }

    public func parseLine(_ data: Data, fallbackProject: String) -> UsageRecord? {
        JSONLParser.parseLine(data, fallbackProject: fallbackProject)
    }
}

/// Resolves a persisted provider type id back into a live provider.
/// Add future tools (Codex, etc.) here once their local log format is confirmed.
public enum ProviderRegistry {
    /// Provider types the UI can offer when adding a source.
    public static let knownTypes: [(typeId: String, label: String, needsPath: Bool)] = [
        (ClaudeCodeProvider.typeId, "Claude Code", false),
        (GenericClaudeFormatProvider.typeId, "Claude-format folder (custom)", true),
    ]

    public static func provider(typeId: String, displayName: String) -> UsageProvider? {
        switch typeId {
        case ClaudeCodeProvider.typeId:
            return ClaudeCodeProvider(displayName: displayName)
        case GenericClaudeFormatProvider.typeId:
            return GenericClaudeFormatProvider(displayName: displayName)
        default:
            return nil
        }
    }
}

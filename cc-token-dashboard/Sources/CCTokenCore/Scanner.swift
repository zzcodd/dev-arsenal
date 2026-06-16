import Foundation

/// Locates Claude Code transcript files under ~/.claude/projects.
public enum TranscriptScanner {
    /// Where Claude Code keeps its transcripts. Honors the `CLAUDE_CONFIG_DIR`
    /// override (some users relocate ~/.claude), otherwise the default home location.
    /// This is a per-user relative convention, so it resolves correctly for anyone —
    /// each person reads their own data, no hardcoded paths.
    ///
    /// Note: a GUI app launched at login via launchd won't inherit shell env vars, so
    /// `CLAUDE_CONFIG_DIR` set in ~/.zshrc only applies when launched from a terminal.
    public static var rootURL: URL {
        if let override = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"],
           !override.isEmpty {
            let expanded = (override as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded, isDirectory: true)
                .appendingPathComponent("projects", isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    /// All `*.jsonl` transcript files, paired with a fallback project name
    /// derived from the containing directory (used only when a line lacks `cwd`).
    public static func allTranscripts(root: URL = rootURL) -> [(url: URL, fallbackProject: String)] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        var out: [(URL, String)] = []
        for dir in dirs {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let fallback = cleanProjectName(dir.lastPathComponent)
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for f in files where f.pathExtension == "jsonl" {
                out.append((f, fallback))
            }
        }
        return out
    }

    /// Recursively find every `*.jsonl` under `root`, with the containing directory's name
    /// as the fallback project. Used by providers whose log layout isn't the fixed
    /// ~/.claude/projects shape (e.g. a user-pointed directory).
    public static func jsonlFilesRecursive(under root: URL) -> [(url: URL, fallbackProject: String)] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil,
                                             options: [.skipsHiddenFiles]) else { return [] }
        var out: [(URL, String)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let parent = url.deletingLastPathComponent().lastPathComponent
            out.append((url, cleanProjectName(parent)))
        }
        return out
    }

    /// "-Users-zhangyu-project-ccDir-cc-token-dashboard" → "cc-token-dashboard".
    /// Hyphens in the original folder name are ambiguous, so this is best-effort;
    /// per-record `cwd` is the accurate source and overrides this.
    static func cleanProjectName(_ dirName: String) -> String {
        let parts = dirName.split(separator: "-").map(String.init)
        return parts.last ?? dirName
    }
}

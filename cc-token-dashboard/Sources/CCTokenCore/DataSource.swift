import Foundation

/// A data source the user configures in Settings: a provider type + where to read from.
/// Persisted (as JSON) to UserDefaults by the app.
public struct DataSource: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var providerType: String   // matches a UsageProvider.typeId
    public var name: String           // display name; also stamped as record.source
    public var path: String           // root dir; empty => use the provider's default
    public var enabled: Bool

    public init(id: String, providerType: String, name: String, path: String, enabled: Bool) {
        self.id = id
        self.providerType = providerType
        self.name = name
        self.path = path
        self.enabled = enabled
    }
}

public extension DataSource {
    /// First-run config: just Claude Code at its default location.
    static var defaults: [DataSource] {
        [DataSource(id: "claude-code-default",
                    providerType: ClaudeCodeProvider.typeId,
                    name: "Claude Code",
                    path: "",
                    enabled: true)]
    }

    /// Resolve to a live provider + the effective root URL, or nil if it can't be resolved
    /// (e.g. a custom-folder source with no path set).
    func resolved() -> (provider: UsageProvider, root: URL)? {
        guard let provider = ProviderRegistry.provider(typeId: providerType, displayName: name) else {
            return nil
        }
        let root: URL
        if !path.isEmpty {
            root = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        } else if let def = provider.defaultRoot() {
            root = def
        } else {
            return nil
        }
        return (provider, root)
    }
}

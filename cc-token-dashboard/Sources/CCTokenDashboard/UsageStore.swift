import Foundation
import SwiftUI
import UserNotifications
import CCTokenCore

/// What the always-visible menu bar shows.
enum MenuBarMetric: String, CaseIterable, Identifiable {
    case todayTokens = "Today's tokens"
    case todayCost   = "Today's cost"
    case session     = "Current session"
    var id: String { rawValue }
}

/// Owns all state: parses transcripts, watches the filesystem, and publishes
/// aggregated usage to the UI. Lives on the main actor; heavy scanning is hopped
/// to a background queue and results are merged back here.
@MainActor
final class UsageStore: ObservableObject {
    // Selected range drives the popover. Persisted.
    @AppStorage("range") var rangeRaw: String = TimeRange.today.rawValue {
        didSet { recompute() }
    }
    @AppStorage("menuBarMetric") var metricRaw: String = MenuBarMetric.todayTokens.rawValue {
        didSet { updateMenuBarText() }
    }
    @AppStorage("notifyEnabled") var notifyEnabled: Bool = false
    @AppStorage("notifyThreshold") var notifyThreshold: Int = 5_000_000

    @Published private(set) var aggregated = AggregatedUsage()   // for selected range
    @Published private(set) var today = AggregatedUsage()         // always today
    @Published private(set) var sessionTokens = 0
    @Published private(set) var menuBarText = "…"
    @Published private(set) var lastUpdated = Date(timeIntervalSince1970: 0)
    @Published private(set) var isScanning = false
    /// Configured data sources (Claude Code + any custom folders). Persisted as JSON.
    @Published private(set) var dataSources: [DataSource] = []

    var range: TimeRange { TimeRange(rawValue: rangeRaw) ?? .today }
    var metric: MenuBarMetric { MenuBarMetric(rawValue: metricRaw) ?? .todayTokens }

    private let sourcesKey = "dataSources"
    private var fileRecords: [URL: [UsageRecord]] = [:]
    private var offsets: [URL: UInt64] = [:]
    private var currentSessionFile: URL?
    private var watchers: [FSEventsWatcher] = []
    private var notifiedToday = false
    private var refreshScheduled = false

    init() {
        loadDataSources()
        start()
    }

    private func start() {
        Task { await fullScan() }
        rebuildWatchers()
    }

    // MARK: - Data sources

    private func loadDataSources() {
        if let data = UserDefaults.standard.data(forKey: sourcesKey),
           let decoded = try? JSONDecoder().decode([DataSource].self, from: data),
           !decoded.isEmpty {
            dataSources = decoded
        } else {
            dataSources = DataSource.defaults
        }
    }

    private func saveDataSources() {
        if let data = try? JSONEncoder().encode(dataSources) {
            UserDefaults.standard.set(data, forKey: sourcesKey)
        }
    }

    /// Replace the source list (from Settings), persist it, and re-scan from scratch.
    func setDataSources(_ new: [DataSource]) {
        dataSources = new
        saveDataSources()
        fileRecords.removeAll()
        offsets.removeAll()
        currentSessionFile = nil
        rebuildWatchers()
        Task { await fullScan() }
    }

    func addSource(_ ds: DataSource) { setDataSources(dataSources + [ds]) }
    func removeSource(id: String) { setDataSources(dataSources.filter { $0.id != id }) }
    func updateSource(_ ds: DataSource) { setDataSources(dataSources.map { $0.id == ds.id ? ds : $0 }) }

    /// Enabled sources resolved to (provider, source name, root). Skips unresolvable ones.
    private func resolvedSources() -> [(provider: UsageProvider, source: String, root: URL)] {
        dataSources.compactMap { ds in
            guard ds.enabled, let r = ds.resolved() else { return nil }
            return (r.provider, ds.name, r.root)
        }
    }

    private func rebuildWatchers() {
        watchers.forEach { $0.stop() }
        watchers = resolvedSources().map { s in
            let w = FSEventsWatcher(path: s.root.path) { [weak self] in
                Task { @MainActor in self?.scheduleRefresh() }
            }
            w.start()
            return w
        }
    }

    /// Coalesce rapid FSEvents into at most one refresh per ~300ms.
    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            refreshScheduled = false
            await self.refresh()
        }
    }

    private func fullScan() async {
        isScanning = true
        await parse()
        isScanning = false
    }

    private func refresh() async {
        await parse()
    }

    /// Incrementally parse every enabled source's files from their stored offsets
    /// (off the main thread), stamping each record with its source name.
    private func parse() async {
        let sources = resolvedSources()
        let snapshot = offsets
        let parsed: [(URL, [UsageRecord], UInt64)] = await Task.detached(priority: .utility) {
            var results: [(URL, [UsageRecord], UInt64)] = []
            for s in sources {
                for f in s.provider.transcripts(root: s.root) {
                    let start = snapshot[f.url] ?? 0
                    let r = JSONLParser.read(at: f.url, fromOffset: start) { line in
                        guard var rec = s.provider.parseLine(line, fallbackProject: f.fallbackProject)
                        else { return nil }
                        rec.source = s.source
                        return rec
                    }
                    if !r.records.isEmpty || snapshot[f.url] == nil {
                        results.append((f.url, r.records, r.newOffset))
                    }
                }
            }
            return results
        }.value

        var newestTimestamp = currentSessionFile.flatMap { fileRecords[$0]?.last?.timestamp }
            ?? Date(timeIntervalSince1970: 0)
        for (url, records, newOffset) in parsed {
            offsets[url] = newOffset
            if !records.isEmpty {
                fileRecords[url, default: []].append(contentsOf: records)
                if let last = records.last?.timestamp, last >= newestTimestamp {
                    newestTimestamp = last
                    currentSessionFile = url
                }
            }
        }
        recompute()
    }

    private func recompute() {
        let master = Aggregator.dedupe(fileRecords.values.flatMap { $0 })
        aggregated = Aggregator.aggregate(master, range: range)
        today = Aggregator.aggregate(master, range: .today)

        if let file = currentSessionFile {
            let cal = Calendar.current
            let dayStart = cal.startOfDay(for: Date())
            let recs = Aggregator.dedupe(fileRecords[file] ?? [])
            sessionTokens = recs.filter { $0.timestamp >= dayStart }.reduce(0) { $0 + $1.total }
        }

        lastUpdated = Date()
        updateMenuBarText()
        checkThreshold()
    }

    private func updateMenuBarText() {
        switch metric {
        case .todayTokens: menuBarText = Format.tokens(today.totalTokens)
        case .todayCost:   menuBarText = Format.cost(today.estimatedCostUSD)
        case .session:     menuBarText = Format.tokens(sessionTokens)
        }
    }

    // MARK: - Threshold notification

    private func checkThreshold() {
        guard notifyEnabled, notifyThreshold > 0 else { return }
        // Reset the "already notified" flag at the start of a new day.
        if !Calendar.current.isDateInToday(lastUpdated) { notifiedToday = false }
        if today.totalTokens >= notifyThreshold && !notifiedToday {
            notifiedToday = true
            sendNotification(total: today.totalTokens)
        }
    }

    func requestNotificationAuthIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendNotification(total: Int) {
        let content = UNMutableNotificationContent()
        content.title = "CC token usage high"
        content.body = "Today reached \(Format.tokens(total)) tokens (limit \(Format.tokens(notifyThreshold)))."
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}

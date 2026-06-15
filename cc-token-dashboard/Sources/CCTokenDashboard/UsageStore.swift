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

    var range: TimeRange { TimeRange(rawValue: rangeRaw) ?? .today }
    var metric: MenuBarMetric { MenuBarMetric(rawValue: metricRaw) ?? .todayTokens }

    private var fileRecords: [URL: [UsageRecord]] = [:]
    private var offsets: [URL: UInt64] = [:]
    private var currentSessionFile: URL?
    private var watcher: FSEventsWatcher?
    private var notifiedToday = false
    private var refreshScheduled = false

    init() {
        start()
    }

    private func start() {
        Task { await fullScan() }
        let watcher = FSEventsWatcher(path: TranscriptScanner.rootURL.path) { [weak self] in
            Task { @MainActor in self?.scheduleRefresh() }
        }
        watcher.start()
        self.watcher = watcher
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
        let transcripts = TranscriptScanner.allTranscripts()
        await parse(transcripts)
        isScanning = false
    }

    private func refresh() async {
        await parse(TranscriptScanner.allTranscripts())
    }

    /// Incrementally parse each file from its stored offset (off the main thread).
    private func parse(_ transcripts: [(url: URL, fallbackProject: String)]) async {
        let snapshot = offsets
        let parsed: [(URL, [UsageRecord], UInt64)] = await Task.detached(priority: .utility) {
            var results: [(URL, [UsageRecord], UInt64)] = []
            for t in transcripts {
                let start = snapshot[t.url] ?? 0
                let r = JSONLParser.parse(at: t.url, fallbackProject: t.fallbackProject, fromOffset: start)
                if !r.records.isEmpty || snapshot[t.url] == nil {
                    results.append((t.url, r.records, r.newOffset))
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

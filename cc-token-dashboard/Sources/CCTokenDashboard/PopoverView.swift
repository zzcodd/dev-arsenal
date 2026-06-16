import SwiftUI
import AppKit
import Charts
import CCTokenCore

struct PopoverView: View {
    @EnvironmentObject var store: UsageStore
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if showSettings {
                SettingsPanel()
            } else {
                hero
                tokenBreakdown
                Divider()
                trend
                Divider()
                breakdown("By project", store.aggregated.byProject, limit: 5)
                if store.aggregated.bySource.count > 1 {
                    Divider()
                    breakdown("By source", store.aggregated.bySource, limit: 6)
                }
            }
            footer
        }
        .padding(16)
        .frame(width: 320)
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Picker("", selection: $store.rangeRaw) {
                ForEach(TimeRange.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)
            .disabled(showSettings)

            Spacer()
            Button { withAnimation { showSettings.toggle() } } label: {
                Image(systemName: showSettings ? "chart.bar.fill" : "gearshape")
            }
            .buttonStyle(.plain)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Format.grouped(store.aggregated.totalTokens))
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            HStack(spacing: 6) {
                Text("tokens").foregroundStyle(.secondary)
                Text("≈ \(Format.cost(store.aggregated.estimatedCostUSD))")
                    .foregroundStyle(.secondary)
                    .help("Equivalent market value — not your actual subscription bill")
            }
            .font(.callout)
        }
    }

    private var tokenBreakdown: some View {
        let a = store.aggregated
        return Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow {
                stat("Input", a.input, .blue)
                stat("Output", a.output, .green)
            }
            GridRow {
                stat("Cache write", a.cacheCreation, .orange)
                stat("Cache read", a.cacheRead, .gray)
            }
        }
    }

    private func stat(_ label: String, _ value: Int, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(Format.tokens(value)).monospacedDigit()
        }
        .font(.caption)
    }

    private var trend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Last 7 days").font(.caption).foregroundStyle(.secondary)
            Chart(store.aggregated.dailyTotals) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Tokens", day.tokens)
                )
                .foregroundStyle(Color.accentColor.gradient)
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 64)
        }
    }

    /// Shared breakdown list — used for both "By project" and "By source".
    private func breakdown(_ title: String, _ items: [NamedTotal], limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            if items.isEmpty {
                Text("No usage in this range").font(.caption).foregroundStyle(.tertiary)
            }
            ForEach(items.prefix(limit)) { item in
                let pct = store.aggregated.totalTokens > 0
                    ? Double(item.tokens) / Double(store.aggregated.totalTokens) : 0
                HStack(spacing: 8) {
                    Text(item.name).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Format.tokens(item.tokens)).monospacedDigit().foregroundStyle(.secondary)
                    Text("\(Int(pct * 100))%").monospacedDigit()
                        .foregroundStyle(.tertiary).frame(width: 34, alignment: .trailing)
                }
                .font(.caption)
                ProgressView(value: pct).tint(.accentColor).scaleEffect(x: 1, y: 0.6, anchor: .center)
            }
        }
    }

    private var footer: some View {
        HStack {
            if store.isScanning {
                ProgressView().controlSize(.small)
                Text("Scanning…").font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("Last 5h: \(Format.tokens(store.aggregated.last5hTokens))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(updatedString).font(.caption2).foregroundStyle(.tertiary)
            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power").font(.caption2)
            }
            .buttonStyle(.plain)
            .help("Quit")
        }
    }

    private var updatedString: String {
        guard store.lastUpdated.timeIntervalSince1970 > 0 else { return "" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return "Updated \(f.string(from: store.lastUpdated))"
    }
}

// MARK: - Settings

struct SettingsPanel: View {
    @EnvironmentObject var store: UsageStore
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var thresholdM: Double = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings").font(.headline)

            // Data sources — Claude Code plus any custom Claude-format folders.
            VStack(alignment: .leading, spacing: 6) {
                Text("Data sources").font(.caption).foregroundStyle(.secondary)
                ForEach(store.dataSources) { ds in
                    sourceRow(ds)
                }
                Button { addCustomFolder() } label: {
                    Label("Add folder…", systemImage: "plus")
                }
                .buttonStyle(.link).font(.caption)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Menu bar shows").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $store.metricRaw) {
                    ForEach(MenuBarMetric.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                .labelsHidden()
            }

            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, v in LaunchAtLogin.set(v) }

            Divider()

            Toggle("Notify when today exceeds threshold", isOn: $store.notifyEnabled)
                .onChange(of: store.notifyEnabled) { _, v in
                    if v { store.requestNotificationAuthIfNeeded() }
                }
            if store.notifyEnabled {
                HStack {
                    Text("Threshold").font(.caption).foregroundStyle(.secondary)
                    Slider(value: $thresholdM, in: 1...50, step: 1)
                    Text("\(Int(thresholdM))M").monospacedDigit().frame(width: 36, alignment: .trailing)
                }
                .onChange(of: thresholdM) { _, v in store.notifyThreshold = Int(v) * 1_000_000 }
            }
        }
        .onAppear { thresholdM = Double(store.notifyThreshold) / 1_000_000 }
    }

    // MARK: - Data source rows

    @ViewBuilder
    private func sourceRow(_ ds: DataSource) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { ds.enabled },
                set: { var c = ds; c.enabled = $0; store.updateSource(c) }
            ))
            .labelsHidden().toggleStyle(.switch).controlSize(.mini)

            VStack(alignment: .leading, spacing: 0) {
                Text(ds.name).font(.caption).lineLimit(1)
                Text(ds.path.isEmpty ? "default · ~/.claude/projects" : ds.path)
                    .font(.caption2).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle)
            }

            Spacer(minLength: 4)

            Button { chooseFolder(for: ds) } label: { Image(systemName: "folder") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Choose folder")

            if ds.id != "claude-code-default" {
                Button { store.removeSource(id: ds.id) } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Remove source")
            } else if !ds.path.isEmpty {
                Button { var c = ds; c.path = ""; store.updateSource(c) } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Reset to default location")
            }
        }
    }

    private func chooseFolder(for ds: DataSource) {
        guard let url = pickDirectory() else { return }
        var c = ds; c.path = url.path; store.updateSource(c)
    }

    private func addCustomFolder() {
        guard let url = pickDirectory() else { return }
        let name = url.lastPathComponent.isEmpty ? "Custom" : url.lastPathComponent
        store.addSource(DataSource(id: UUID().uuidString,
                                   providerType: GenericClaudeFormatProvider.typeId,
                                   name: name, path: url.path, enabled: true))
    }

    private func pickDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use This Folder"
        panel.message = "Pick a folder containing Claude-Code-format .jsonl logs"
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }
}

import SwiftUI
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
                projectList
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

    private var projectList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("By project").font(.caption).foregroundStyle(.secondary)
            if store.aggregated.byProject.isEmpty {
                Text("No usage in this range").font(.caption).foregroundStyle(.tertiary)
            }
            ForEach(store.aggregated.byProject.prefix(5)) { p in
                let pct = store.aggregated.totalTokens > 0
                    ? Double(p.tokens) / Double(store.aggregated.totalTokens) : 0
                HStack(spacing: 8) {
                    Text(p.name).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Format.tokens(p.tokens)).monospacedDigit().foregroundStyle(.secondary)
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
}

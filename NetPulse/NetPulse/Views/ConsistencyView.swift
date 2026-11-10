import SwiftUI

struct ConsistencyView: View {
    enum TimeRange: Double, CaseIterable, Identifiable {
        case fiveMinutes = 300
        case hour = 3600
        case sixHours = 21600
        case day = 86400

        var id: Double { rawValue }
        var label: String {
            switch self {
            case .fiveMinutes: return "5 min"
            case .hour: return "1 hr"
            case .sixHours: return "6 hr"
            case .day: return "24 hr"
            }
        }
    }

    @EnvironmentObject private var monitor: ConnectionMonitor
    @State private var range: TimeRange = .hour
    @State private var confirmClear = false
    @ScaledMetric private var chartHeight = ChartSize.regular

    var body: some View {
        let samples = monitor.samples(inLast: range.rawValue)
        let summary = ConsistencySummary.build(samples: samples)

        NavigationStack {
            List {
                Section {
                    Picker("Time Range", selection: $range) {
                        ForEach(TimeRange.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .accessibilityIdentifier("consistency.range")
                }

                Section("Summary") {
                    StatRow {
                        StatTile(label: "Uptime",
                                 value: summary.uptimePercent.map { String(format: "%.1f%%", $0) } ?? "–",
                                 tint: uptimeTint(summary.uptimePercent))
                        StatTile(label: "Drops",
                                 value: "\(summary.drops.count)",
                                 tint: summary.drops.isEmpty ? .primary : .statusCritical)
                        StatTile(label: "Longest drop",
                                 value: summary.drops.isEmpty ? "–" : Format.duration(summary.longestDrop))
                    }
                    StatRow {
                        StatTile(label: "Avg response", value: Format.ms(summary.averageLatencyMs))
                        StatTile(label: "Jitter", value: Format.ms(summary.jitterMs))
                        StatTile(label: "Monitored",
                                 value: summary.monitoredSeconds > 0 ? Format.duration(summary.monitoredSeconds) : "–")
                    }
                }

                Section {
                    LatencyChart(samples: samples, window: range.rawValue)
                        .frame(height: chartHeight)
                        .padding(.vertical, Spacing.xs)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Spacing.l) { legend }
                        VStack(alignment: .leading, spacing: Spacing.xs) { legend }
                    }
                } header: {
                    Text("Response Time")
                } footer: {
                    Text("Blank stretches are times NetPulse wasn't open.")
                }

                Section("Drop Log") {
                    if summary.drops.isEmpty {
                        ContentUnavailableView(samples.isEmpty ? "Nothing Recorded Yet" : "No Drops",
                                               systemImage: samples.isEmpty ? "chart.xyaxis.line" : "checkmark.circle",
                                               description: Text(samples.isEmpty
                                                                 ? "Keep NetPulse open to record your connection."
                                                                 : "Your connection held for this whole period."))
                    }
                    ForEach(summary.drops.reversed()) { drop in
                        DropRow(drop: drop)
                    }
                }
            }
            .navigationTitle("Consistency")
            .toolbar {
                Menu {
                    Button("Clear History", systemImage: "trash", role: .destructive) { confirmClear = true }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
            .confirmationDialog("Delete all recorded connection history?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Delete History", role: .destructive) { monitor.clearHistory() }
            }
        }
    }

    @ViewBuilder
    private var legend: some View {
        LegendItem(color: .chartLine, text: "Response time")
        LegendItem(color: .chartDropRule, text: "Connection dropped")
    }

    private func uptimeTint(_ value: Double?) -> Color {
        guard let value else { return .primary }
        if value >= 99.5 { return .statusGood }
        return value >= 97 ? .statusCaution : .statusCritical
    }
}

private struct DropRow: View {
    let drop: DropEvent

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(Color.statusCritical)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(drop.start.formatted(date: .abbreviated, time: .standard))
                    .font(.rowTitle)
                    .monospacedDigit()
                Text(drop.network == .offline ? "No network" : "On \(drop.network.label)")
                    .font(.rowDetail)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Spacing.s)
            Text(drop.ongoing ? "Ongoing · \(Format.duration(drop.duration))" : Format.duration(drop.duration))
                .font(.rowValue)
                .foregroundStyle(Color.statusCritical)
        }
        .accessibilityElement(children: .combine)
    }
}

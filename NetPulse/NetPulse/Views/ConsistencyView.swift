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

    var body: some View {
        let samples = monitor.samples(inLast: range.rawValue)
        let summary = ConsistencySummary.build(samples: samples)

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Time range", selection: $range) {
                        ForEach(TimeRange.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Card {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 12) {
                                StatTile(label: "Uptime",
                                         value: summary.uptimePercent.map { String(format: "%.1f%%", $0) } ?? "–",
                                         tint: uptimeTint(summary.uptimePercent))
                                StatTile(label: "Drops",
                                         value: "\(summary.drops.count)",
                                         tint: summary.drops.isEmpty ? .primary : .red)
                                StatTile(label: "Longest drop",
                                         value: summary.drops.isEmpty ? "–" : Format.duration(summary.longestDrop))
                            }
                            HStack(spacing: 12) {
                                StatTile(label: "Avg response", value: Format.ms(summary.averageLatencyMs))
                                StatTile(label: "Jitter", value: Format.ms(summary.jitterMs))
                                StatTile(label: "Monitored",
                                         value: summary.monitoredSeconds > 0 ? Format.duration(summary.monitoredSeconds) : "–")
                            }
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Response time")
                                .font(.headline)
                            LatencyChart(samples: samples, window: range.rawValue)
                                .frame(height: 220)
                            HStack(spacing: 16) {
                                legend(color: .accentColor, text: "Response time")
                                legend(color: .red, text: "Connection dropped")
                            }
                            Text("Blank stretches are times NetPulse wasn't open.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Drop log")
                                .font(.headline)
                                .padding(.bottom, 8)
                            if summary.drops.isEmpty {
                                Text(samples.isEmpty ? "Nothing recorded in this period yet." : "No drops in this period.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 4)
                            }
                            ForEach(summary.drops.reversed()) { drop in
                                Divider()
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(drop.start.formatted(date: .abbreviated, time: .standard))
                                            .font(.subheadline)
                                            .monospacedDigit()
                                        Text(drop.network == .offline ? "No network" : "On \(drop.network.label)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(drop.ongoing ? "Ongoing · \(Format.duration(drop.duration))" : Format.duration(drop.duration))
                                        .font(.subheadline.weight(.semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(.red)
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Consistency")
            .toolbar {
                Menu {
                    Button("Clear history", role: .destructive) { confirmClear = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            .confirmationDialog("Delete all recorded connection history?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Delete history", role: .destructive) { monitor.clearHistory() }
            }
        }
    }

    private func uptimeTint(_ value: Double?) -> Color {
        guard let value else { return .primary }
        if value >= 99.5 { return .green }
        return value >= 97 ? .orange : .red
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 14, height: 4)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }
}

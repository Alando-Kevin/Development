import SwiftUI
import Charts

struct LiveView: View {
    @EnvironmentObject private var monitor: ConnectionMonitor
    @AppStorage("monitoringEnabled") private var monitoringEnabled = true
    @AppStorage("keepAwake") private var keepAwake = false

    var body: some View {
        let quality = monitor.quality
        let recent = monitor.samples(inLast: 120)
        let lastDrop = Analysis.drops(in: monitor.samples(inLast: 3600)).last

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Card {
                        HStack(alignment: .center, spacing: 20) {
                            SignalBars(bars: quality.bars, color: quality.level.color, height: 64)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(quality.level.rawValue)
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(quality.level.color)
                                if quality.level != .unknown {
                                    Text("Strength \(quality.score) / 100")
                                        .font(.subheadline)
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                                Label(monitor.networkLabel, systemImage: monitor.network.symbol)
                                    .font(.subheadline.weight(.medium))
                                    .padding(.top, 4)
                            }
                            Spacer(minLength: 0)
                        }
                    }

                    Card {
                        VStack(spacing: 10) {
                            detailRow("Connection", monitor.networkLabel)
                            if monitor.network == .wifi {
                                Divider()
                                detailRow("Wi-Fi name", monitor.wifiName ?? "Not available")
                            }
                            Divider()
                            detailRow("Provider", monitor.provider ?? (monitor.network == .offline ? "–" : "Looking up…"))
                        }
                    }

                    Card {
                        HStack(spacing: 12) {
                            StatTile(label: "Response time", value: Format.ms(quality.latencyMs))
                            StatTile(label: "Jitter", value: Format.ms(quality.jitterMs))
                            StatTile(label: "Failed checks",
                                     value: String(format: "%.0f%%", quality.lossPercent),
                                     tint: quality.lossPercent > 0 ? .red : .primary)
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Last 2 minutes")
                                .font(.headline)
                            LatencyChart(samples: recent, window: 120)
                                .frame(height: 150)
                            dropStatus(lastDrop)
                        }
                    }

                    Card {
                        VStack(spacing: 12) {
                            Toggle("Monitor connection", isOn: $monitoringEnabled)
                            Divider()
                            Toggle("Keep screen awake", isOn: $keepAwake)
                        }
                    }

                    Text("Strength is worked out from how quickly and reliably the internet responds, checked every \(Int(ConnectionMonitor.interval)) seconds. iOS doesn't let apps read the raw signal level (dBm). Monitoring runs while NetPulse is open.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("NetPulse")
            .onChange(of: monitoringEnabled) { _, enabled in
                if enabled { monitor.start() } else { monitor.stop() }
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .font(.subheadline)
    }

    @ViewBuilder
    private func dropStatus(_ drop: DropEvent?) -> some View {
        if let drop, drop.ongoing {
            Label("Connection down for \(Format.duration(drop.duration))", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.red)
        } else if let drop {
            Label("Last drop \(drop.end.formatted(date: .omitted, time: .shortened)), lasted \(Format.duration(drop.duration))",
                  systemImage: "arrow.down.to.line")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            Label("No drops in the last hour", systemImage: "checkmark.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

/// Response time over time, with red bands where the connection dropped.
struct LatencyChart: View {
    let samples: [ProbeSample]
    let window: TimeInterval

    var body: some View {
        let summary = ConsistencySummary.build(samples: samples)
        let now = Date()
        let peak = max(100, (summary.points.map(\.latencyMs).max() ?? 0) * 1.15)

        Chart {
            ForEach(summary.drops) { drop in
                RectangleMark(xStart: .value("Start", drop.start),
                              xEnd: .value("End", drop.end),
                              yStart: .value("Low", 0),
                              yEnd: .value("High", peak))
                    .foregroundStyle(Color.red.opacity(0.22))
                RuleMark(x: .value("Drop", drop.start))
                    .foregroundStyle(Color.red)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            ForEach(summary.points) { point in
                LineMark(x: .value("Time", point.time),
                         y: .value("Response time", point.latencyMs),
                         series: .value("Segment", point.segment))
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .chartXScale(domain: now.addingTimeInterval(-window)...now)
        .chartYScale(domain: 0...peak)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let ms = value.as(Double.self) { Text("\(Int(ms)) ms") }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: window > 600 ? Date.FormatStyle.dateTime.hour().minute() : Date.FormatStyle.dateTime.hour().minute().second())
            }
        }
        .overlay {
            if samples.isEmpty {
                Text("No measurements yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

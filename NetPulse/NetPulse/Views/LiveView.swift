import SwiftUI
import Charts

struct LiveView: View {
    @EnvironmentObject private var monitor: ConnectionMonitor
    @AppStorage("monitoringEnabled") private var monitoringEnabled = true
    @AppStorage("keepAwake") private var keepAwake = false
    @ScaledMetric private var chartHeight = ChartSize.compact

    var body: some View {
        let quality = monitor.quality
        let recent = monitor.samples(inLast: 120)
        let lastDrop = Analysis.drops(in: monitor.samples(inLast: 3600)).last

        NavigationStack {
            List {
                Section {
                    HStack(spacing: Spacing.l) {
                        SignalGlyph(network: monitor.network, quality: quality)
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Label(quality.level.rawValue, systemImage: quality.level.symbol)
                                .font(.heroTitle)
                                .foregroundStyle(quality.level.color)
                            if quality.level != .unknown {
                                Text("Strength \(quality.score) out of 100")
                                    .font(.subheadline)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .contentTransition(.numericText())
                            }
                        }
                    }
                    .padding(.vertical, Spacing.s)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("live.strength")
                }

                Section {
                    LabeledContent("Type", value: monitor.networkLabel)
                    if monitor.network == .wifi {
                        LabeledContent("Wi-Fi Name", value: monitor.wifiName ?? "Not available")
                    }
                    LabeledContent("Provider", value: monitor.provider ?? (monitor.network == .offline ? "–" : "Looking up…"))
                } header: {
                    Text("Connection")
                }

                Section("Last Minute") {
                    StatRow {
                        StatTile(label: "Response time", value: Format.ms(quality.latencyMs))
                        StatTile(label: "Jitter", value: Format.ms(quality.jitterMs))
                        StatTile(label: "Failed checks",
                                 value: String(format: "%.0f%%", quality.lossPercent),
                                 tint: quality.lossPercent > 0 ? .statusCritical : .primary)
                    }
                }

                Section("Last 2 Minutes") {
                    LatencyChart(samples: recent, window: 120)
                        .frame(height: chartHeight)
                        .padding(.vertical, Spacing.xs)
                    dropStatus(lastDrop)
                }

                Section {
                    Toggle("Monitor Connection", isOn: $monitoringEnabled)
                        .accessibilityIdentifier("live.monitorToggle")
                    Toggle("Keep Screen Awake", isOn: $keepAwake)
                        .accessibilityIdentifier("live.keepAwakeToggle")
                } footer: {
                    Text("Strength is worked out from how quickly and reliably the internet responds, checked every \(Int(ConnectionMonitor.interval)) seconds. iOS doesn't let apps read the raw signal level. Monitoring runs while NetPulse is open.")
                }
            }
            .navigationTitle("NetPulse")
            .animation(.snappy, value: quality.score)
            .sensoryFeedback(.impact, trigger: monitor.network == .cellular)
            .sensoryFeedback(trigger: quality.level == .offline) { _, isDown in
                isDown ? .warning : .success
            }
            .onChange(of: monitoringEnabled) { _, enabled in
                if enabled { monitor.start() } else { monitor.stop() }
            }
        }
    }

    @ViewBuilder
    private func dropStatus(_ drop: DropEvent?) -> some View {
        if let drop, drop.ongoing {
            Label("Connection down for \(Format.duration(drop.duration))", systemImage: "exclamationmark.triangle.fill")
                .font(.rowTitle.weight(.medium))
                .foregroundStyle(Color.statusCritical)
        } else if let drop {
            Label("Last drop \(drop.end.formatted(date: .omitted, time: .shortened)), lasted \(Format.duration(drop.duration))",
                  systemImage: "arrow.down.to.line")
                .font(.rowTitle)
                .foregroundStyle(.secondary)
        } else {
            Label("No drops in the last hour", systemImage: "checkmark.circle")
                .font(.rowTitle)
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
                    .foregroundStyle(Color.chartDropBand)
                RuleMark(x: .value("Drop", drop.start))
                    .foregroundStyle(Color.chartDropRule)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            ForEach(summary.points) { point in
                LineMark(x: .value("Time", point.time),
                         y: .value("Response time", point.latencyMs),
                         series: .value("Segment", point.segment))
                    .foregroundStyle(Color.chartLine)
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
                Label("No measurements yet", systemImage: "chart.xyaxis.line")
                    .font(.rowTitle)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Response time chart")
        .accessibilityValue(accessibilitySummary(summary))
    }

    private func accessibilitySummary(_ summary: ConsistencySummary) -> String {
        guard let average = summary.averageLatencyMs else { return "No measurements yet" }
        let drops = summary.drops.count
        let dropText = drops == 0 ? "no drops" : drops == 1 ? "1 drop" : "\(drops) drops"
        return "Average \(Int(average.rounded())) milliseconds, \(dropText)"
    }
}

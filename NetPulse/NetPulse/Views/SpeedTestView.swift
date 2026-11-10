import SwiftUI

struct SpeedTestView: View {
    @EnvironmentObject private var monitor: ConnectionMonitor
    @EnvironmentObject private var speedTest: SpeedTestEngine
    @State private var confirmClear = false

    var body: some View {
        let isRunning = speedTest.phase.isRunning
        let history = Array(speedTest.results.dropFirst())

        NavigationStack {
            List {
                Section {
                    VStack(spacing: Spacing.l) {
                        readout
                        ProgressView(value: speedTest.progress)
                            .opacity(isRunning ? 1 : 0)
                            .accessibilityHidden(!isRunning)
                        if isRunning {
                            Button(role: .cancel) {
                                speedTest.cancel()
                            } label: {
                                Text("Cancel").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .accessibilityIdentifier("speed.cancel")
                        } else {
                            Button {
                                runTest()
                            } label: {
                                Text("Run Speed Test").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .accessibilityIdentifier("speed.run")
                        }
                    }
                    .padding(.vertical, Spacing.s)

                    if case .failed(let message) = speedTest.phase {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.rowTitle)
                            .foregroundStyle(Color.statusCritical)
                    }
                } footer: {
                    Text("A test takes about 20 seconds and uses real data: a few MB on a slow connection, several hundred MB on a very fast one. On cellular, run it only when you need to.")
                }

                if let latest = speedTest.results.first, !isRunning {
                    Section {
                        StatRow {
                            StatTile(label: "Download", value: "\(Format.mbps(latest.downloadMbps)) Mbps")
                            StatTile(label: "Upload", value: "\(Format.mbps(latest.uploadMbps)) Mbps")
                        }
                        StatRow {
                            StatTile(label: "Ping", value: Format.ms(latest.pingMs))
                            StatTile(label: "Jitter", value: Format.ms(latest.jitterMs))
                        }
                    } header: {
                        Text("Latest Result")
                    } footer: {
                        Text(latest.connectionSummary)
                    }
                }

                Section("History") {
                    if history.isEmpty {
                        ContentUnavailableView("No Earlier Tests",
                                               systemImage: "speedometer",
                                               description: Text("Results from your speed tests are kept here."))
                    }
                    ForEach(history) { result in
                        HistoryRow(result: result)
                    }
                    .onDelete { offsets in
                        speedTest.remove(ids: Set(offsets.map { history[$0].id }))
                    }
                }
            }
            .navigationTitle("Speed Test")
            .onAppear {
                // Launching with "-autoRunSpeedTest YES" starts a test straight away (used for automated checks).
                if UserDefaults.standard.bool(forKey: "autoRunSpeedTest"), speedTest.results.isEmpty, !isRunning {
                    runTest()
                }
            }
            .animation(.snappy, value: speedTest.phase)
            .sensoryFeedback(.success, trigger: speedTest.results.count)
            .toolbar {
                if !speedTest.results.isEmpty {
                    Menu {
                        Button("Clear History", systemImage: "trash", role: .destructive) { confirmClear = true }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog("Delete all speed test results?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Delete Results", role: .destructive) { speedTest.clearHistory() }
            }
        }
    }

    private func runTest() {
        speedTest.run { [monitor] in
            (monitor.network, monitor.radio, monitor.wifiName, monitor.provider)
        }
    }

    private var phaseLabel: String {
        switch speedTest.phase {
        case .ping: return "Checking ping…"
        case .download: return "Testing download"
        case .upload: return "Testing upload"
        case .idle, .failed: return "On \(monitor.networkLabel)"
        }
    }

    private var readout: some View {
        VStack(spacing: Spacing.xs) {
            Text(phaseLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HeroNumber(value: bigNumber, unit: "Mbps")
            if speedTest.phase == .upload, let down = speedTest.partialDownload {
                Text("Download \(Format.mbps(down)) Mbps")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var bigNumber: String {
        if speedTest.phase == .download || speedTest.phase == .upload {
            return Format.mbps(speedTest.liveMbps)
        }
        if let latest = speedTest.results.first, speedTest.phase == .idle {
            return Format.mbps(latest.downloadMbps)
        }
        return "–"
    }
}

private struct HistoryRow: View {
    let result: SpeedTestResult

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(result.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.rowTitle)
                Text(result.connectionSummary)
                    .font(.rowDetail)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Spacing.s)
            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                Label("\(Format.mbps(result.downloadMbps)) Mbps", systemImage: "arrow.down")
                    .accessibilityLabel("Download \(Format.mbps(result.downloadMbps)) megabits per second")
                Label("\(Format.mbps(result.uploadMbps)) Mbps", systemImage: "arrow.up")
                    .accessibilityLabel("Upload \(Format.mbps(result.uploadMbps)) megabits per second")
            }
            .font(.rowTitle)
            .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

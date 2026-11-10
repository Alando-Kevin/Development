import SwiftUI

struct SpeedTestView: View {
    @EnvironmentObject private var monitor: ConnectionMonitor
    @EnvironmentObject private var speedTest: SpeedTestEngine

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Card {
                        VStack(spacing: 16) {
                            readout
                            ProgressView(value: speedTest.progress)
                                .opacity(speedTest.phase.isRunning ? 1 : 0)
                            Button {
                                if speedTest.phase.isRunning {
                                    speedTest.cancel()
                                } else {
                                    speedTest.run(network: monitor.network, radio: monitor.radio)
                                }
                            } label: {
                                Text(speedTest.phase.isRunning ? "Cancel" : "Run speed test")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(speedTest.phase.isRunning ? Color.gray : Color.accentColor)

                            if case .failed(let message) = speedTest.phase {
                                Text(message)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                                    .multilineTextAlignment(.center)
                            }
                        }
                    }

                    if let latest = speedTest.results.first, !speedTest.phase.isRunning {
                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Latest result")
                                    .font(.headline)
                                HStack(spacing: 12) {
                                    StatTile(label: "Download", value: "\(Format.mbps(latest.downloadMbps)) Mbps")
                                    StatTile(label: "Upload", value: "\(Format.mbps(latest.uploadMbps)) Mbps")
                                }
                                HStack(spacing: 12) {
                                    StatTile(label: "Ping", value: Format.ms(latest.pingMs))
                                    StatTile(label: "Jitter", value: Format.ms(latest.jitterMs))
                                }
                            }
                        }
                    }

                    if speedTest.results.count > 1 {
                        Card {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("History")
                                    .font(.headline)
                                    .padding(.bottom, 8)
                                ForEach(speedTest.results.dropFirst()) { result in
                                    Divider()
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(result.date.formatted(date: .abbreviated, time: .shortened))
                                                .font(.subheadline)
                                            Text(result.networkLabel)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Label("\(Format.mbps(result.downloadMbps)) Mbps", systemImage: "arrow.down")
                                            Label("\(Format.mbps(result.uploadMbps)) Mbps", systemImage: "arrow.up")
                                        }
                                        .font(.subheadline)
                                        .monospacedDigit()
                                    }
                                    .padding(.vertical, 8)
                                }
                            }
                        }
                    }

                    Text("A test takes about 20 seconds and uses real data: a few MB on a slow connection, several hundred MB on a very fast one. On cellular, run it only when you need to.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Speed test")
            .toolbar {
                if !speedTest.results.isEmpty {
                    Menu {
                        Button("Clear history", role: .destructive) { speedTest.clearHistory() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
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
        VStack(spacing: 4) {
            Text(phaseLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(bigNumber)
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("Mbps")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            if speedTest.phase == .upload, let down = speedTest.partialDownload {
                Text("Download \(Format.mbps(down)) Mbps")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
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

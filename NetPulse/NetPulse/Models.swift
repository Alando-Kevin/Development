import Foundation

/// The kind of connection the phone is using.
enum NetworkKind: String, Codable {
    case wifi, cellular, wired, other, offline

    var label: String {
        switch self {
        case .wifi: return "Wi-Fi"
        case .cellular: return "Cellular"
        case .wired: return "Wired"
        case .other: return "Other"
        case .offline: return "Offline"
        }
    }

    var symbol: String {
        switch self {
        case .wifi: return "wifi"
        case .cellular: return "antenna.radiowaves.left.and.right"
        case .wired: return "cable.connector"
        case .other: return "network"
        case .offline: return "wifi.slash"
        }
    }
}

/// One connectivity check. `latencyMs` is nil when the check failed (no response in time).
struct ProbeSample: Codable, Identifiable {
    let time: Date
    let latencyMs: Double?
    let network: NetworkKind

    var id: Date { time }
    var failed: Bool { latencyMs == nil }
}

/// A period where consecutive checks failed.
struct DropEvent: Identifiable {
    let start: Date
    let end: Date
    let network: NetworkKind
    /// True when the drop is still happening (it runs up to the newest sample).
    let ongoing: Bool

    var id: Date { start }
    var duration: TimeInterval { end.timeIntervalSince(start) }
}

struct SpeedTestResult: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let downloadMbps: Double
    let uploadMbps: Double
    let pingMs: Double
    let jitterMs: Double
    let network: NetworkKind
    let radio: String?

    var networkLabel: String {
        if network == .cellular, let radio { return radio }
        return network.label
    }
}

/// How good the connection is right now, derived from recent checks.
struct Quality {
    enum Level: String {
        case excellent = "Excellent"
        case good = "Good"
        case fair = "Fair"
        case poor = "Poor"
        case offline = "No connection"
        case unknown = "Measuring…"
    }

    let score: Int          // 0...100
    let level: Level
    let bars: Int           // 0...4
    let latencyMs: Double?  // median
    let jitterMs: Double?
    let lossPercent: Double

    static let unknown = Quality(score: 0, level: .unknown, bars: 0, latencyMs: nil, jitterMs: nil, lossPercent: 0)
}

enum Analysis {
    /// Two samples further apart than this mean the app was not monitoring in between.
    static let gapThreshold: TimeInterval = 12

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    /// Average change between consecutive successful checks.
    static func jitter(_ values: [Double]) -> Double? {
        guard values.count > 1 else { return nil }
        var total = 0.0
        for i in 1..<values.count { total += abs(values[i] - values[i - 1]) }
        return total / Double(values.count - 1)
    }

    /// Scores the connection from recent samples (the caller passes roughly the last minute).
    static func quality(from samples: [ProbeSample]) -> Quality {
        guard let last = samples.last else { return .unknown }
        let latencies = samples.compactMap(\.latencyMs)
        let loss = Double(samples.count - latencies.count) / Double(samples.count) * 100
        let recentFailures = samples.suffix(2).filter(\.failed).count

        if latencies.isEmpty || (last.failed && recentFailures == min(2, samples.count)) {
            return Quality(score: 0, level: .offline, bars: 0,
                           latencyMs: median(latencies), jitterMs: jitter(latencies), lossPercent: loss)
        }

        let med = median(latencies) ?? 0
        let jit = jitter(latencies) ?? 0
        let latencyPenalty = min(40, max(0, (med - 30) / 270 * 40))
        let jitterPenalty = min(20, max(0, (jit - 5) / 95 * 20))
        let lossPenalty = min(60, loss * 2)
        let score = Int(max(1, 100 - latencyPenalty - jitterPenalty - lossPenalty).rounded())

        let level: Quality.Level
        let bars: Int
        switch score {
        case 85...: level = .excellent; bars = 4
        case 65..<85: level = .good; bars = 3
        case 40..<65: level = .fair; bars = 2
        default: level = .poor; bars = 1
        }
        return Quality(score: score, level: level, bars: bars, latencyMs: med, jitterMs: jit, lossPercent: loss)
    }

    /// Groups consecutive failed checks into drops. Samples must be in time order.
    static func drops(in samples: [ProbeSample]) -> [DropEvent] {
        var result: [DropEvent] = []
        var runStart: ProbeSample?
        var runLast: ProbeSample?

        func close(at end: Date, ongoing: Bool) {
            if let start = runStart {
                result.append(DropEvent(start: start.time, end: end, network: start.network, ongoing: ongoing))
            }
            runStart = nil
            runLast = nil
        }

        for sample in samples {
            if let last = runLast, sample.time.timeIntervalSince(last.time) > gapThreshold {
                // Monitoring stopped during the drop; end it at the last failed check.
                close(at: last.time.addingTimeInterval(2), ongoing: false)
            }
            if sample.failed {
                if runStart == nil { runStart = sample }
                runLast = sample
            } else if runStart != nil {
                close(at: sample.time, ongoing: false)
            }
        }
        if let last = runLast {
            close(at: last.time.addingTimeInterval(2), ongoing: true)
        }
        return result
    }
}

/// One point on the consistency chart. Many samples are averaged into one point for long ranges.
struct ChartPoint: Identifiable {
    let time: Date
    let latencyMs: Double
    /// Points with the same segment are joined by a line; a new segment starts after a drop or gap.
    let segment: Int
    var id: Date { time }
}

struct ConsistencySummary {
    let points: [ChartPoint]
    let drops: [DropEvent]
    let uptimePercent: Double?
    let averageLatencyMs: Double?
    let jitterMs: Double?
    let longestDrop: TimeInterval
    let monitoredSeconds: TimeInterval

    static func build(samples: [ProbeSample], maxPoints: Int = 240) -> ConsistencySummary {
        let drops = Analysis.drops(in: samples)
        let latencies = samples.compactMap(\.latencyMs)
        let uptime: Double? = samples.isEmpty ? nil : Double(latencies.count) / Double(samples.count) * 100
        let average: Double? = latencies.isEmpty ? nil : latencies.reduce(0, +) / Double(latencies.count)

        // Time actually spent monitoring (ignores periods the app was closed).
        var monitored: TimeInterval = 0
        if samples.count > 1 {
            for i in 1..<samples.count {
                let delta = samples[i].time.timeIntervalSince(samples[i - 1].time)
                if delta <= Analysis.gapThreshold { monitored += delta }
            }
        }

        // Downsample into buckets so the chart stays fast over 24 hours.
        var points: [ChartPoint] = []
        let bucketSize = max(1, Int((Double(samples.count) / Double(maxPoints)).rounded(.up)))
        var segment = 0
        var previousTime: Date?
        var previousFailed = false
        var index = 0
        while index < samples.count {
            let bucket = samples[index..<min(index + bucketSize, samples.count)]
            index += bucketSize
            guard let first = bucket.first else { continue }
            if let previousTime, first.time.timeIntervalSince(previousTime) > Analysis.gapThreshold * Double(bucketSize) {
                segment += 1
            }
            let values = bucket.compactMap(\.latencyMs)
            if values.isEmpty {
                previousFailed = true
            } else {
                if previousFailed { segment += 1 }
                previousFailed = false
                points.append(ChartPoint(time: first.time,
                                         latencyMs: values.reduce(0, +) / Double(values.count),
                                         segment: segment))
            }
            previousTime = bucket.last?.time
        }

        return ConsistencySummary(points: points,
                                  drops: drops,
                                  uptimePercent: uptime,
                                  averageLatencyMs: average,
                                  jitterMs: Analysis.jitter(latencies),
                                  longestDrop: drops.map(\.duration).max() ?? 0,
                                  monitoredSeconds: monitored)
    }
}

enum Format {
    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(max(1, s))s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        return "\(s / 3600)h \((s % 3600) / 60)m"
    }

    static func ms(_ value: Double?) -> String {
        guard let value else { return "–" }
        return "\(Int(value.rounded())) ms"
    }

    static func mbps(_ value: Double) -> String {
        value >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}

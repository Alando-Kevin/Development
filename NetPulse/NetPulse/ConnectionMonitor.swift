import Foundation
import Network
import CoreTelephony

/// Sends one small request and reports how long the reply took.
struct Prober {
    /// Two independent servers, so one provider having a bad moment is not recorded as a drop.
    static let targets: [URL] = [
        URL(string: "https://cp.cloudflare.com/generate_204")!,
        URL(string: "https://www.apple.com/library/test/success.html")!
    ]
    static let timeout: TimeInterval = 2.5

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = Prober.timeout
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    /// Returns the response time in milliseconds, or nil if no server answered.
    func measure() async -> Double? {
        for url in Prober.targets {
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = Prober.timeout
            let started = DispatchTime.now().uptimeNanoseconds
            do {
                let (_, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode < 500 {
                    return Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
                }
            } catch {
                continue
            }
        }
        return nil
    }
}

/// Watches the connection: what kind it is, how quickly it responds, and when it drops.
@MainActor
final class ConnectionMonitor: ObservableObject {
    /// Seconds between checks. Lower is more detailed but uses more battery and data.
    static let interval: TimeInterval = 2
    /// How much history to keep.
    static let retention: TimeInterval = 24 * 3600

    @Published private(set) var samples: [ProbeSample] = []
    @Published private(set) var network: NetworkKind = .offline
    @Published private(set) var radio: String?
    @Published private(set) var isLowDataMode = false
    @Published private(set) var isMonitoring = false

    private let pathMonitor = NWPathMonitor()
    private let telephony = CTTelephonyNetworkInfo()
    private let prober = Prober()
    private var loop: Task<Void, Never>?
    private var unsavedCount = 0

    init() {
        let cutoff = Date().addingTimeInterval(-Self.retention)
        samples = Store.load([ProbeSample].self, from: Store.samplesFile)?.filter { $0.time > cutoff } ?? []

        pathMonitor.pathUpdateHandler = { [weak self] path in
            let kind = Self.kind(of: path)
            let lowData = path.isConstrained
            Task { @MainActor in
                self?.network = kind
                self?.isLowDataMode = lowData
                self?.refreshRadio()
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "netpulse.path"))
    }

    /// Label for the current connection, e.g. "Wi-Fi" or "5G".
    var networkLabel: String {
        if network == .cellular, let radio { return radio }
        return network.label
    }

    var quality: Quality {
        guard isMonitoring else { return .unknown }
        let cutoff = Date().addingTimeInterval(-60)
        return Analysis.quality(from: samples.suffix(40).filter { $0.time > cutoff })
    }

    func samples(inLast window: TimeInterval) -> [ProbeSample] {
        let cutoff = Date().addingTimeInterval(-window)
        // Samples are in time order, so search from the end.
        var start = samples.count
        while start > 0 && samples[start - 1].time > cutoff { start -= 1 }
        return Array(samples[start...])
    }

    func start() {
        guard loop == nil else { return }
        isMonitoring = true
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let started = Date()
                let latency = await self.prober.measure()
                if Task.isCancelled { return }
                self.record(ProbeSample(time: started, latencyMs: latency, network: latency == nil && self.network == .offline ? .offline : self.network))
                let wait = max(0.25, Self.interval - Date().timeIntervalSince(started))
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        isMonitoring = false
        save()
    }

    func clearHistory() {
        samples = []
        save()
    }

    func save() {
        unsavedCount = 0
        Store.save(samples, to: Store.samplesFile)
    }

    private func record(_ sample: ProbeSample) {
        samples.append(sample)
        unsavedCount += 1
        if unsavedCount >= 30 {
            let cutoff = Date().addingTimeInterval(-Self.retention)
            if let first = samples.first, first.time < cutoff {
                samples.removeAll { $0.time < cutoff }
            }
            save()
        }
    }

    private func refreshRadio() {
        guard network == .cellular,
              let technology = telephony.serviceCurrentRadioAccessTechnology?.values.first else {
            radio = nil
            return
        }
        switch technology {
        case CTRadioAccessTechnologyNR, CTRadioAccessTechnologyNRNSA: radio = "5G"
        case CTRadioAccessTechnologyLTE: radio = "LTE"
        default: radio = "3G"
        }
    }

    private nonisolated static func kind(of path: NWPath) -> NetworkKind {
        guard path.status == .satisfied else { return .offline }
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.cellular) { return .cellular }
        if path.usesInterfaceType(.wiredEthernet) { return .wired }
        return .other
    }
}

/// Saves history as JSON files in the app's private storage.
enum Store {
    static let samplesFile = "samples.json"
    static let speedTestsFile = "speedtests.json"

    private static func url(_ name: String) -> URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }

    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let url = url(name), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, to name: String) {
        guard let url = url(name), let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

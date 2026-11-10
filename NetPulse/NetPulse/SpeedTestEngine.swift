import Foundation

/// Counts bytes moving through a URLSession and keeps the transfers going until stopped.
private final class TransferMeter: NSObject, URLSessionDataDelegate {
    enum Mode { case download, upload }

    private let mode: Mode
    private let makeTask: (URLSession) -> URLSessionTask
    private let lock = NSLock()
    private var total: Int64 = 0
    private var failures = 0
    private var active = true

    init(mode: Mode, makeTask: @escaping (URLSession) -> URLSessionTask) {
        self.mode = mode
        self.makeTask = makeTask
    }

    var bytes: Int64 {
        lock.lock(); defer { lock.unlock() }
        return total
    }

    /// True when the server keeps refusing, so the test should give up.
    var hasGivenUp: Bool {
        lock.lock(); defer { lock.unlock() }
        return failures >= 6
    }

    func stop() {
        lock.lock(); active = false; lock.unlock()
    }

    func startTask(in session: URLSession) {
        makeTask(session).resume()
    }

    private func add(_ count: Int64) {
        lock.lock(); total += count; lock.unlock()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if mode == .download { add(Int64(data.count)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        if mode == .upload { add(bytesSent) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        let ok = error == nil && (200..<300).contains(status)
        lock.lock()
        if !ok { failures += 1 }
        let shouldRestart = active && failures < 6
        lock.unlock()
        // Each transfer is a fixed size; start another so the stream runs for the whole test.
        if shouldRestart { startTask(in: session) }
    }
}

/// Runs an on-demand speed test against Cloudflare's public speed test servers.
@MainActor
final class SpeedTestEngine: ObservableObject {
    enum Phase: Equatable {
        case idle, ping, download, upload
        case failed(String)

        var isRunning: Bool { self == .ping || self == .download || self == .upload }
    }

    struct TestError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var liveMbps: Double = 0
    @Published private(set) var progress: Double = 0
    @Published private(set) var partialDownload: Double?
    @Published private(set) var partialPing: Double?
    @Published private(set) var results: [SpeedTestResult] = []

    private static let downloadURL = URL(string: "https://speed.cloudflare.com/__down?bytes=25000000")!
    private static let pingURL = URL(string: "https://speed.cloudflare.com/__down?bytes=0")!
    private static let uploadURL = URL(string: "https://speed.cloudflare.com/__up")!
    private static let transferSeconds: TimeInterval = 8
    private static let streams = 4

    private var task: Task<Void, Never>?

    init() {
        results = Store.load([SpeedTestResult].self, from: Store.speedTestsFile) ?? []
    }

    func run(network: NetworkKind, radio: String?) {
        guard !phase.isRunning else { return }
        partialDownload = nil
        partialPing = nil
        liveMbps = 0
        progress = 0
        task = Task {
            do {
                phase = .ping
                let (ping, jitter) = try await measurePing()
                partialPing = ping

                phase = .download
                let down = try await measureTransfer(.download, progressStart: 0.1)
                partialDownload = down

                phase = .upload
                let up = try await measureTransfer(.upload, progressStart: 0.55)

                let result = SpeedTestResult(date: Date(), downloadMbps: down, uploadMbps: up,
                                             pingMs: ping, jitterMs: jitter, network: network, radio: radio)
                results.insert(result, at: 0)
                if results.count > 200 { results.removeLast(results.count - 200) }
                Store.save(results, to: Store.speedTestsFile)
                progress = 1
                phase = .idle
            } catch is CancellationError {
                phase = .idle
            } catch {
                phase = .failed(error.localizedDescription)
            }
            liveMbps = 0
        }
    }

    func cancel() {
        task?.cancel()
    }

    func clearHistory() {
        results = []
        Store.save(results, to: Store.speedTestsFile)
    }

    private func makeSession(delegate: URLSessionDelegate?) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 10
        config.httpMaximumConnectionsPerHost = Self.streams
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    private func measurePing() async throws -> (ping: Double, jitter: Double) {
        let session = makeSession(delegate: nil)
        defer { session.invalidateAndCancel() }
        var times: [Double] = []
        for attempt in 0..<7 {
            try Task.checkCancellation()
            let started = DispatchTime.now().uptimeNanoseconds
            if (try? await session.data(from: Self.pingURL)) != nil {
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
                // The first request includes connection setup, so it is not counted.
                if attempt > 0 { times.append(elapsed) }
            }
            progress = 0.1 * Double(attempt + 1) / 7
        }
        try Task.checkCancellation()
        guard let ping = Analysis.median(times) else {
            throw TestError(message: "Couldn't reach the speed test server. Check your connection and try again.")
        }
        return (ping, Analysis.jitter(times) ?? 0)
    }

    private func measureTransfer(_ mode: TransferMeter.Mode, progressStart: Double) async throws -> Double {
        let payload = Data(count: 4_000_000)
        let meter = TransferMeter(mode: mode) { session in
            switch mode {
            case .download:
                return session.dataTask(with: Self.downloadURL)
            case .upload:
                var request = URLRequest(url: Self.uploadURL)
                request.httpMethod = "POST"
                request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                return session.uploadTask(with: request, from: payload)
            }
        }
        let session = makeSession(delegate: meter)
        defer {
            meter.stop()
            session.invalidateAndCancel()
        }
        for _ in 0..<Self.streams { meter.startTask(in: session) }

        let started = Date()
        var warmTime: Date?
        var warmBytes: Int64 = 0
        var lastTime = started
        var lastBytes: Int64 = 0
        liveMbps = 0

        while Date().timeIntervalSince(started) < Self.transferSeconds {
            try await Task.sleep(nanoseconds: 250_000_000)
            let now = Date()
            let bytes = meter.bytes
            // Skip the first second while the connections ramp up.
            if warmTime == nil, now.timeIntervalSince(started) >= 1 {
                warmTime = now
                warmBytes = bytes
            }
            let instant = Double(bytes - lastBytes) * 8 / 1_000_000 / max(0.001, now.timeIntervalSince(lastTime))
            liveMbps = liveMbps == 0 ? instant : liveMbps * 0.6 + instant * 0.4
            lastTime = now
            lastBytes = bytes
            progress = progressStart + 0.45 * min(1, now.timeIntervalSince(started) / Self.transferSeconds)
            if meter.hasGivenUp { break }
        }

        let finalBytes = meter.bytes
        guard let warmTime, finalBytes > warmBytes else {
            throw TestError(message: mode == .download
                            ? "The download test didn't receive any data. Try again in a moment."
                            : "The upload test couldn't send any data. Try again in a moment.")
        }
        return Double(finalBytes - warmBytes) * 8 / 1_000_000 / max(0.001, Date().timeIntervalSince(warmTime))
    }
}

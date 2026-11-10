import Foundation
import Darwin

/// Reads the phone's own byte counters for each network interface.
/// These count all traffic on the device since it was last restarted, not just NetPulse's.
enum InterfaceCounters {
    /// Returns counters keyed like "pdp_ip0.in" (mobile data) and "en0.out" (Wi-Fi).
    static func read() -> [String: UInt64] {
        var result: [String: UInt64] = [:]
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return result }
        defer { freeifaddrs(list) }

        var pointer = list
        while let current = pointer {
            let interface = current.pointee
            pointer = interface.ifa_next
            guard let address = interface.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_LINK),
                  let raw = interface.ifa_data else { continue }
            let name = String(cString: interface.ifa_name)
            guard name.hasPrefix("pdp_ip") || name == "en0" else { continue }
            let data = raw.assumingMemoryBound(to: if_data.self).pointee
            result["\(name).in"] = UInt64(data.ifi_ibytes)
            result["\(name).out"] = UInt64(data.ifi_obytes)
        }
        return result
    }

    static func isMobile(_ key: String) -> Bool { key.hasPrefix("pdp_ip") }

    /// When the phone last started. Counters reset to zero at that moment.
    static func bootTime() -> Date {
        var time = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &time, &size, nil, 0) == 0 else { return .distantPast }
        return Date(timeIntervalSince1970: TimeInterval(time.tv_sec))
    }
}

struct DayUsage: Codable, Identifiable {
    let day: Date          // start of the day
    var mobile: Int64 = 0
    var wifi: Int64 = 0
    var id: Date { day }
}

/// A change between Wi-Fi and mobile data.
struct SwitchEvent: Codable, Identifiable {
    var id = UUID()
    let time: Date
    let from: NetworkKind
    let to: NetworkKind
    /// Mobile data used during the period that just ended.
    let mobileBytesBefore: Int64
    /// True when the change happened while NetPulse was closed and was noticed on reopening.
    let whileClosed: Bool
}

/// A comparison between what NetPulse measured and the balance the provider reports.
struct BalanceCheck: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let reportedRemaining: Int64
    let measuredRemaining: Int64
    /// Combined size of the bundles that were active when the check was made.
    let totalSize: Int64

    /// Positive when the provider has deducted more than this iPhone measured.
    var difference: Int64 { measuredRemaining - reportedRemaining }

    /// Differences smaller than this are treated as a match.
    var tolerance: Int64 { max(50_000_000, totalSize / 20) }

    var isDiscrepancy: Bool { abs(difference) > tolerance }
}

/// A data bundle the user bought.
struct DataBundle: Codable, Identifiable {
    var id = UUID()
    let purchasedAt: Date
    let sizeBytes: Int64
    var validDays: Int? = nil
    var cost: Double? = nil
    var usedBytes: Int64 = 0
    var endedAt: Date? = nil
    /// Exact expiry, when it was read from a provider message.
    var explicitExpiry: Date? = nil

    var expiresAt: Date? {
        explicitExpiry ?? validDays.map { purchasedAt.addingTimeInterval(TimeInterval($0) * 86400) }
    }

    var isActive: Bool {
        if endedAt != nil { return false }
        if let expiresAt, expiresAt < Date() { return false }
        return usedBytes < sizeBytes
    }

    var measuredRemaining: Int64 { max(0, sizeBytes - usedBytes) }
}

/// A provider message that was handed to NetPulse, and what was done with it.
struct LoggedMessage: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let outcome: String
}

struct UsageState: Codable {
    var lastCounters: [String: UInt64] = [:]
    var lastBoot: Date? = nil
    var days: [DayUsage] = []
    var bundles: [DataBundle] = []
    var switches: [SwitchEvent] = []
    var lastConnected: NetworkKind? = nil
    var mobileSinceSwitch: Int64 = 0
    /// Comparisons with the provider's balance, newest first.
    var checks: [BalanceCheck]? = nil
    var messages: [LoggedMessage]? = nil
}

/// Tracks how much mobile data and Wi-Fi data the phone uses, data bundles, and network changes.
@MainActor
final class DataUsageTracker: ObservableObject {
    /// One shared tracker, so the Shortcuts action and the app's screens use the same data.
    static let shared = DataUsageTracker()

    static let file = "usage.json"
    static let sampleInterval: TimeInterval = 5
    static let daysKept = 90

    @Published private(set) var state: UsageState

    private var loop: Task<Void, Never>?
    private var unsaved = 0
    private var hasSeenNetwork = false

    init() {
        state = Store.load(UsageState.self, from: Self.file) ?? UsageState()
    }

    // MARK: Reading

    var today: DayUsage {
        let start = Calendar.current.startOfDay(for: Date())
        return state.days.last { $0.day == start } ?? DayUsage(day: start)
    }

    func mobileUsed(inLastDays count: Int) -> Int64 {
        days(count).reduce(0) { $0 + $1.mobile }
    }

    /// One entry per day for the last `count` days, including days with no usage.
    func days(_ count: Int) -> [DayUsage] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        return (0..<count).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: start) else { return nil }
            return state.days.first { $0.day == day } ?? DayUsage(day: day)
        }
    }

    /// Bundles still running, in the order they are used up: soonest expiry first.
    var activeBundles: [DataBundle] {
        state.bundles.filter(\.isActive).sorted(by: Self.usedBefore)
    }

    /// What should be left across every active bundle.
    var totalRemaining: Int64 { activeBundles.reduce(0) { $0 + $1.measuredRemaining } }

    var latestCheck: BalanceCheck? { state.checks?.first }

    private static func usedBefore(_ a: DataBundle, _ b: DataBundle) -> Bool {
        let aExpiry = a.expiresAt ?? .distantFuture
        let bExpiry = b.expiresAt ?? .distantFuture
        return aExpiry == bExpiry ? a.purchasedAt < b.purchasedAt : aExpiry < bExpiry
    }

    var pastBundles: [DataBundle] { state.bundles.filter { !$0.isActive } }

    /// Total cost of bundles bought in the current calendar month.
    var spentThisMonth: Double {
        let calendar = Calendar.current
        return state.bundles
            .filter { calendar.isDate($0.purchasedAt, equalTo: Date(), toGranularity: .month) }
            .compactMap(\.cost)
            .reduce(0, +)
    }

    // MARK: Sampling

    func start() {
        guard loop == nil else { return }
        sample()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.sampleInterval * 1_000_000_000))
                if Task.isCancelled { return }
                self?.sample()
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        sample()
        save()
    }

    /// Adds whatever the phone has used since the last reading.
    func sample() {
        let counters = InterfaceCounters.read()
        let boot = InterfaceCounters.bootTime()
        let rebooted = state.lastBoot.map { abs($0.timeIntervalSince(boot)) > 300 } ?? false
        var mobile: Int64 = 0
        var wifi: Int64 = 0

        // The very first reading only sets the starting point.
        if !state.lastCounters.isEmpty {
            for (key, value) in counters {
                let delta: UInt64
                if let last = state.lastCounters[key], !rebooted {
                    if value >= last {
                        delta = value - last
                    } else if last > 3_500_000_000 {
                        // The counter is 32-bit and wrapped past 4 GB.
                        delta = value + 4_294_967_296 - last
                    } else {
                        delta = value
                    }
                } else {
                    delta = value
                }
                if InterfaceCounters.isMobile(key) { mobile += Int64(delta) } else { wifi += Int64(delta) }
            }
        }
        state.lastCounters = counters
        state.lastBoot = boot
        guard mobile > 0 || wifi > 0 else { return }

        let day = Calendar.current.startOfDay(for: Date())
        if let index = state.days.lastIndex(where: { $0.day == day }) {
            state.days[index].mobile += mobile
            state.days[index].wifi += wifi
        } else {
            state.days.append(DayUsage(day: day, mobile: mobile, wifi: wifi))
            if state.days.count > Self.daysKept { state.days.removeFirst(state.days.count - Self.daysKept) }
        }
        state.mobileSinceSwitch += mobile
        // With stacked bundles, take usage from the one that expires first and spill into the next.
        var left = mobile
        for bundle in activeBundles where left > 0 {
            guard let index = state.bundles.firstIndex(where: { $0.id == bundle.id }) else { continue }
            let taken = min(left, bundle.measuredRemaining)
            state.bundles[index].usedBytes += taken
            left -= taken
        }

        unsaved += 1
        if unsaved >= 12 { save() }
    }

    /// Call whenever the connection type changes. Records moves between Wi-Fi and mobile data.
    func networkChanged(to kind: NetworkKind) {
        guard kind == .wifi || kind == .cellular else { return }
        sample()
        let noticedOnLaunch = !hasSeenNetwork
        hasSeenNetwork = true
        if let previous = state.lastConnected, previous != kind {
            state.switches.insert(SwitchEvent(time: Date(), from: previous, to: kind,
                                              mobileBytesBefore: state.mobileSinceSwitch,
                                              whileClosed: noticedOnLaunch), at: 0)
            if state.switches.count > 100 { state.switches.removeLast(state.switches.count - 100) }
            state.mobileSinceSwitch = 0
        }
        state.lastConnected = kind
        save()
    }

    // MARK: Bundles

    func addBundle(sizeBytes: Int64, validDays: Int?, cost: Double?, expires: Date? = nil) {
        sample()
        state.bundles.insert(DataBundle(purchasedAt: Date(), sizeBytes: sizeBytes, validDays: validDays,
                                        cost: cost, explicitExpiry: expires), at: 0)
        save()
    }

    func endBundle(id: UUID) {
        guard let index = state.bundles.firstIndex(where: { $0.id == id }) else { return }
        state.bundles[index].endedAt = Date()
        save()
    }

    /// Compares the measured balance with what the provider says is left.
    func recordBalance(reportedRemaining: Int64) {
        sample()
        let active = activeBundles
        guard !active.isEmpty else { return }
        var checks = state.checks ?? []
        checks.insert(BalanceCheck(date: Date(),
                                   reportedRemaining: reportedRemaining,
                                   measuredRemaining: totalRemaining,
                                   totalSize: active.reduce(0) { $0 + $1.sizeBytes }), at: 0)
        if checks.count > 50 { checks.removeLast(checks.count - 50) }
        state.checks = checks
        save()
    }

    /// Reads a provider message and records the bundle or balance in it. Returns a sentence saying what happened.
    @discardableResult
    func apply(message: String) -> String {
        let outcome: String
        switch MessageParser.parse(message) {
        case .purchase(let size, let cost, let expires):
            addBundle(sizeBytes: size, validDays: nil, cost: cost, expires: expires)
            outcome = "Added a \(Format.bytes(size)) bundle."
        case .balance(let remaining):
            if activeBundles.isEmpty {
                outcome = "Balance of \(Format.bytes(remaining)) noted, but there is no active bundle to compare it with."
            } else {
                recordBalance(reportedRemaining: remaining)
                if let check = latestCheck, check.isDiscrepancy {
                    outcome = "Provider balance \(Format.bytes(remaining)) differs from the measured balance by \(Format.bytes(abs(check.difference)))."
                } else {
                    outcome = "Provider balance \(Format.bytes(remaining)) matches the measured balance."
                }
            }
        case .unrecognised:
            outcome = "No bundle purchase or data balance found in that message."
        }
        var messages = state.messages ?? []
        messages.insert(LoggedMessage(date: Date(), outcome: outcome), at: 0)
        if messages.count > 30 { messages.removeLast(messages.count - 30) }
        state.messages = messages
        save()
        return outcome
    }

    func removeBundles(ids: Set<UUID>) {
        state.bundles.removeAll { ids.contains($0.id) }
        save()
    }

    func clearSwitches() {
        state.switches = []
        save()
    }

    func save() {
        unsaved = 0
        Store.save(state, to: Self.file)
    }
}

extension Format {
    static func bytes(_ value: Int64) -> String {
        value < 1_000 ? "0 MB" : value.formatted(.byteCount(style: .decimal))
    }
}

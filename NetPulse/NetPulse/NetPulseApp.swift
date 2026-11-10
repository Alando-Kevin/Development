import SwiftUI

@main
struct NetPulseApp: App {
    @StateObject private var monitor = ConnectionMonitor()
    @StateObject private var speedTest = SpeedTestEngine()
    @StateObject private var usage = DataUsageTracker.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("monitoringEnabled") private var monitoringEnabled = true
    @AppStorage("keepAwake") private var keepAwake = false
    /// Which tab to open on. Launching with "-initialTab 3" opens the Data tab (used for screenshots).
    @State private var selectedTab = UserDefaults.standard.integer(forKey: "initialTab")

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                LiveView()
                    .tabItem { Label("Live", systemImage: "waveform.path.ecg") }
                    .tag(0)
                SpeedTestView()
                    .tabItem { Label("Speed", systemImage: "speedometer") }
                    .tag(1)
                ConsistencyView()
                    .tabItem { Label("Consistency", systemImage: "chart.xyaxis.line") }
                    .tag(2)
                DataView()
                    .tabItem { Label("Data", systemImage: "chart.bar.fill") }
                    .tag(3)
            }
            .environmentObject(monitor)
            .environmentObject(speedTest)
            .environmentObject(usage)
            .onChange(of: monitor.network) { _, kind in
                usage.networkChanged(to: kind)
            }
            .onChange(of: scenePhase) { _, phase in
                // iOS pauses apps in the background, so monitoring only runs while NetPulse is open.
                if phase == .active {
                    usage.start()
                    if monitoringEnabled { monitor.start() }
                    UIApplication.shared.isIdleTimerDisabled = keepAwake
                } else if phase == .background {
                    usage.stop()
                    monitor.stop()
                    UIApplication.shared.isIdleTimerDisabled = false
                }
            }
            .onChange(of: keepAwake) { _, value in
                UIApplication.shared.isIdleTimerDisabled = value
            }
            .onAppear {
                usage.start()
                if monitoringEnabled { monitor.start() }
                UIApplication.shared.isIdleTimerDisabled = keepAwake
            }
        }
    }
}

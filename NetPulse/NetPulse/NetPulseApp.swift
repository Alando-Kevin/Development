import SwiftUI

@main
struct NetPulseApp: App {
    @StateObject private var monitor = ConnectionMonitor()
    @StateObject private var speedTest = SpeedTestEngine()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("monitoringEnabled") private var monitoringEnabled = true
    @AppStorage("keepAwake") private var keepAwake = false

    var body: some Scene {
        WindowGroup {
            TabView {
                LiveView()
                    .tabItem { Label("Live", systemImage: "waveform.path.ecg") }
                SpeedTestView()
                    .tabItem { Label("Speed", systemImage: "speedometer") }
                ConsistencyView()
                    .tabItem { Label("Consistency", systemImage: "chart.xyaxis.line") }
            }
            .environmentObject(monitor)
            .environmentObject(speedTest)
            .onChange(of: scenePhase) { _, phase in
                // iOS pauses apps in the background, so monitoring only runs while NetPulse is open.
                if phase == .active {
                    if monitoringEnabled { monitor.start() }
                    UIApplication.shared.isIdleTimerDisabled = keepAwake
                } else if phase == .background {
                    monitor.stop()
                    UIApplication.shared.isIdleTimerDisabled = false
                }
            }
            .onChange(of: keepAwake) { _, value in
                UIApplication.shared.isIdleTimerDisabled = value
            }
            .onAppear {
                if monitoringEnabled { monitor.start() }
                UIApplication.shared.isIdleTimerDisabled = keepAwake
            }
        }
    }
}

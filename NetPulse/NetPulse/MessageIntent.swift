import AppIntents

/// Lets the Shortcuts app hand NetPulse a text message, for example from an automation
/// that runs whenever a message from Safaricom arrives. iOS doesn't let apps read messages themselves.
struct LogProviderMessageIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Safaricom Message"
    static var description = IntentDescription("Reads a bundle purchase or data balance from a Safaricom message and records it in NetPulse.")

    @Parameter(title: "Message")
    var message: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = DataUsageTracker.shared.apply(message: message)
        return .result(dialog: IntentDialog(stringLiteral: outcome))
    }
}

struct NetPulseShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogProviderMessageIntent(),
                    phrases: ["Log a message in \(.applicationName)"],
                    shortTitle: "Log Safaricom Message",
                    systemImageName: "message")
    }
}

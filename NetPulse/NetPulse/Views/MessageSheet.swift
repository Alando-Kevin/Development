import SwiftUI

/// Paste a provider message and NetPulse records the bundle or balance in it.
struct MessageSheet: View {
    @EnvironmentObject private var usage: DataUsageTracker
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @ScaledMetric private var editorHeight = ChartSize.compact

    var body: some View {
        let parsed = MessageParser.parse(text)

        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: editorHeight)
                        .accessibilityLabel("Message text")
                        .accessibilityIdentifier("message.text")
                    PasteButton(payloadType: String.self) { strings in
                        DispatchQueue.main.async { text = strings.first ?? "" }
                    }
                } header: {
                    Text("Message")
                } footer: {
                    Text("Copy the message from Safaricom in Messages, then paste it here. It stays on this iPhone.")
                }

                Section("What NetPulse Found") {
                    switch parsed {
                    case .purchase(let size, let cost, let expires):
                        LabeledContent("Type", value: "Bundle purchase")
                        LabeledContent("Size", value: Format.bytes(size))
                        if let cost {
                            LabeledContent("Cost", value: cost.formatted(.currency(code: Format.currencyCode)))
                        }
                        if let expires {
                            LabeledContent("Expires", value: expires.formatted(date: .abbreviated, time: .shortened))
                        }
                    case .balance(let remaining):
                        LabeledContent("Type", value: "Data balance")
                        LabeledContent("Left", value: Format.bytes(remaining))
                    case .unrecognised:
                        Text(text.isEmpty ? "Paste a message to see what it contains." : "No bundle purchase or data balance found in this message.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Safaricom Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        _ = usage.apply(message: text)
                        dismiss()
                    }
                    .disabled(parsed == .unrecognised)
                }
            }
        }
        .presentationDetents([.large])
    }
}

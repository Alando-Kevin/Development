import SwiftUI
import Charts

struct DataView: View {
    @EnvironmentObject private var usage: DataUsageTracker
    @State private var showAddBundle = false
    @State private var showBalanceCheck = false
    @State private var confirmEnd = false
    @ScaledMetric private var chartHeight = ChartSize.compact

    var body: some View {
        let today = usage.today
        let days = usage.days(14)

        NavigationStack {
            List {
                Section {
                    StatRow {
                        StatTile(label: "Today", value: Format.bytes(today.mobile))
                        StatTile(label: "7 days", value: Format.bytes(usage.mobileUsed(inLastDays: 7)))
                        StatTile(label: "30 days", value: Format.bytes(usage.mobileUsed(inLastDays: 30)))
                    }
                    LabeledContent("Wi-Fi today", value: Format.bytes(today.wifi))
                } header: {
                    Text("Mobile Data Used")
                }

                Section {
                    Chart(days) { day in
                        BarMark(x: .value("Day", day.day, unit: .day),
                                y: .value("Mobile data", Double(day.mobile) / 1_000_000))
                            .foregroundStyle(Color.chartLine)
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let megabytes = value.as(Double.self) { Text("\(Int(megabytes)) MB") }
                            }
                        }
                    }
                    .frame(height: chartHeight)
                    .padding(.vertical, Spacing.xs)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Mobile data by day")
                    .accessibilityValue("\(Format.bytes(usage.mobileUsed(inLastDays: 14))) in the last 14 days")
                } header: {
                    Text("Last 14 Days")
                }

                bundleSection

                if !usage.pastBundles.isEmpty {
                    Section("Past Bundles") {
                        ForEach(usage.pastBundles) { bundle in
                            PastBundleRow(bundle: bundle)
                        }
                        .onDelete { offsets in
                            let past = usage.pastBundles
                            usage.removeBundles(ids: Set(offsets.map { past[$0].id }))
                        }
                    }
                }

                Section {
                    if usage.state.switches.isEmpty {
                        ContentUnavailableView("No Changes Yet",
                                               systemImage: "arrow.left.arrow.right",
                                               description: Text("Moves between Wi-Fi and mobile data are listed here."))
                    }
                    ForEach(usage.state.switches.prefix(30)) { event in
                        SwitchRow(event: event)
                    }
                } header: {
                    Text("Network Changes")
                } footer: {
                    Text("Figures cover everything this iPhone used, including while NetPulse was closed. iOS doesn't show apps which app used the data; for that, open Settings › Mobile Service. Usage before a restart is missed unless you open NetPulse first, so open it about once a day.")
                }
            }
            .navigationTitle("Data")
            .sheet(isPresented: $showAddBundle) {
                AddBundleSheet()
            }
            .sheet(isPresented: $showBalanceCheck) {
                BalanceCheckSheet()
            }
            .confirmationDialog("Stop tracking this bundle?", isPresented: $confirmEnd, titleVisibility: .visible) {
                Button("End Bundle", role: .destructive) { usage.endActiveBundle() }
            }
        }
    }

    @ViewBuilder
    private var bundleSection: some View {
        Section {
            if let bundle = usage.activeBundle {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    ProgressView(value: min(1, Double(bundle.usedBytes) / Double(max(1, bundle.sizeBytes))))
                        .tint(bundle.measuredRemaining == 0 ? Color.statusCritical : Color.accentColor)
                    Text("\(Format.bytes(bundle.usedBytes)) used of \(Format.bytes(bundle.sizeBytes))")
                        .font(.rowTitle)
                        .monospacedDigit()
                }
                .padding(.vertical, Spacing.xs)
                .accessibilityElement(children: .combine)

                LabeledContent("Should be left", value: Format.bytes(bundle.measuredRemaining))
                if let expires = bundle.expiresAt {
                    LabeledContent("Expires", value: expires.formatted(date: .abbreviated, time: .shortened))
                }
                if let check = bundle.checks.first {
                    BalanceCheckRow(bundle: bundle, check: check)
                }
                Button("Compare With Provider Balance", systemImage: "scalemass") { showBalanceCheck = true }
                    .accessibilityIdentifier("data.checkBalance")
                Button("End Bundle", systemImage: "xmark.circle", role: .destructive) { confirmEnd = true }
            } else {
                ContentUnavailableView("No Active Bundle",
                                       systemImage: "simcard",
                                       description: Text("Add the bundle you bought to see how much should be left."))
            }
            Button(usage.activeBundle == nil ? "Add Bundle" : "Add New Bundle", systemImage: "plus") { showAddBundle = true }
                .accessibilityIdentifier("data.addBundle")
        } header: {
            Text("Data Bundle")
        } footer: {
            if usage.spentThisMonth > 0 {
                Text("Spent on bundles this month: \(usage.spentThisMonth.formatted(.currency(code: Format.currencyCode)))")
            }
        }
    }
}

/// The result of comparing the measured balance with the provider's.
private struct BalanceCheckRow: View {
    let bundle: DataBundle
    let check: BalanceCheck

    var body: some View {
        let flagged = bundle.isDiscrepancy(check)
        let amount = Format.bytes(abs(check.difference))

        VStack(alignment: .leading, spacing: Spacing.xs) {
            if !flagged {
                Label("Provider balance matches", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.statusGood)
            } else if check.difference > 0 {
                Label("Provider shows \(amount) less than expected", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.statusCritical)
            } else {
                Label("Provider shows \(amount) more than expected", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(Color.statusCaution)
            }
            Text(detail(flagged: flagged))
                .font(.rowDetail)
                .foregroundStyle(.secondary)
        }
        .font(.rowTitle.weight(.medium))
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private func detail(flagged: Bool) -> String {
        let when = check.date.formatted(date: .abbreviated, time: .shortened)
        let numbers = "Checked \(when). Provider: \(Format.bytes(check.reportedRemaining)) left. Measured: \(Format.bytes(check.measuredRemaining)) left."
        if !flagged { return numbers }
        if check.difference > 0 {
            return numbers + " More was deducted than this iPhone used. Personal Hotspot, another device on the same line, or a restart before NetPulse was opened can explain it. If none apply, raise it with your provider."
        }
        return numbers + " You may have bonus data, or the bundle was larger than entered."
    }
}

private struct PastBundleRow: View {
    let bundle: DataBundle

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(Format.bytes(bundle.sizeBytes))
                    .font(.rowTitle)
                Text("Bought \(bundle.purchasedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.rowDetail)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Spacing.s)
            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                Text("\(Format.bytes(bundle.usedBytes)) used")
                    .font(.rowTitle)
                    .monospacedDigit()
                if let cost = bundle.cost {
                    Text(cost.formatted(.currency(code: Format.currencyCode)))
                        .font(.rowDetail)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SwitchRow: View {
    let event: SwitchEvent

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: event.to.symbol)
                .foregroundStyle(event.to == .cellular ? Color.statusCaution : Color.statusGood)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(event.to == .cellular ? "Switched to mobile data" : "Switched to Wi-Fi")
                    .font(.rowTitle)
                Text(detail)
                    .font(.rowDetail)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts = [event.time.formatted(date: .abbreviated, time: .shortened)]
        if event.whileClosed { parts.append("noticed on opening NetPulse") }
        if event.from == .cellular { parts.append("used \(Format.bytes(event.mobileBytesBefore)) on mobile data") }
        return parts.joined(separator: " · ")
    }
}

/// Units for typing a data amount.
private enum DataUnit: String, CaseIterable, Identifiable {
    case megabytes = "MB"
    case gigabytes = "GB"

    var id: String { rawValue }
    var bytes: Double { self == .megabytes ? 1_000_000 : 1_000_000_000 }
}

private struct AmountField: View {
    let title: LocalizedStringKey
    @Binding var amount: Double?
    @Binding var unit: DataUnit

    var body: some View {
        TextField(title, value: $amount, format: .number)
            .keyboardType(.decimalPad)
        Picker("Unit", selection: $unit) {
            ForEach(DataUnit.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
    }
}

private struct AddBundleSheet: View {
    @EnvironmentObject private var usage: DataUsageTracker
    @Environment(\.dismiss) private var dismiss
    @State private var amount: Double?
    @State private var unit: DataUnit = .gigabytes
    @State private var validDays: Int?
    @State private var cost: Double?

    var body: some View {
        NavigationStack {
            Form {
                Section("Bundle Size") {
                    AmountField(title: "Amount", amount: $amount, unit: $unit)
                }
                Section {
                    TextField("Valid for (days)", value: $validDays, format: .number)
                        .keyboardType(.numberPad)
                    TextField("Cost", value: $cost, format: .number)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Optional")
                } footer: {
                    Text("Add the bundle right after you buy it. NetPulse counts mobile data from this moment, and stops tracking any earlier bundle.")
                }
            }
            .navigationTitle("Add Bundle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let amount, amount > 0 else { return }
                        usage.addBundle(sizeBytes: Int64(amount * unit.bytes),
                                        validDays: validDays.flatMap { $0 > 0 ? $0 : nil },
                                        cost: cost.flatMap { $0 > 0 ? $0 : nil })
                        dismiss()
                    }
                    .disabled((amount ?? 0) <= 0)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct BalanceCheckSheet: View {
    @EnvironmentObject private var usage: DataUsageTracker
    @Environment(\.dismiss) private var dismiss
    @State private var amount: Double?
    @State private var unit: DataUnit = .megabytes

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AmountField(title: "Balance left", amount: $amount, unit: $unit)
                } header: {
                    Text("Provider Balance")
                } footer: {
                    Text("Check your balance with your provider, then enter what it says is left. NetPulse compares it with what this iPhone used.")
                }
            }
            .navigationTitle("Compare Balance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Compare") {
                        guard let amount, amount >= 0 else { return }
                        usage.recordBalance(reportedRemaining: Int64(amount * unit.bytes))
                        dismiss()
                    }
                    .disabled(amount == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

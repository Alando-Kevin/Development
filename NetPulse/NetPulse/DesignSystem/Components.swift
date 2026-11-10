import SwiftUI

/// The system Wi-Fi or cellular symbol, filled according to connection strength.
struct SignalGlyph: View {
    let network: NetworkKind
    let quality: Quality

    @ScaledMetric(relativeTo: .largeTitle) private var size = IconSize.hero

    private var symbolName: String {
        if quality.level == .offline {
            return network == .cellular ? "antenna.radiowaves.left.and.right.slash" : "wifi.slash"
        }
        return network == .cellular ? "cellularbars" : "wifi"
    }

    var body: some View {
        Image(systemName: symbolName, variableValue: Double(quality.bars) / 4)
            .font(.system(size: size))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(quality.level.color)
            .contentTransition(.symbolEffect(.replace))
            .accessibilityHidden(true)
    }
}

/// A label above a value. VoiceOver reads the pair as one item.
struct StatTile: View {
    let label: LocalizedStringKey
    let value: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label)
                .font(.statLabel)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.statValue)
                .foregroundStyle(tint)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Lays stats side by side, and stacks them when the text size is very large.
struct StatRow<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ViewBuilder var content: Content

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.m))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Spacing.m))
        layout { content }
            .padding(.vertical, Spacing.xs)
    }
}

/// A large number with its unit, used for the speed readout.
struct HeroNumber: View {
    let value: String
    let unit: String

    @ScaledMetric(relativeTo: .largeTitle) private var size = IconSize.heroNumber

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Text(value)
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(unit)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A colour swatch with a caption, for chart legends.
struct LegendItem: View {
    let color: Color
    let text: LocalizedStringKey

    var body: some View {
        HStack(spacing: Spacing.s) {
            RoundedRectangle(cornerRadius: Radius.s)
                .fill(color)
                .frame(width: IconSize.legendSwatchWidth, height: IconSize.legendSwatchHeight)
            Text(text)
                .font(.rowDetail)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Stats") {
    List {
        StatRow {
            StatTile(label: "Response time", value: "24 ms")
            StatTile(label: "Jitter", value: "3 ms")
            StatTile(label: "Failed checks", value: "2%", tint: .statusCritical)
        }
        HeroNumber(value: "41.8", unit: "Mbps")
        LegendItem(color: .chartLine, text: "Response time")
    }
}

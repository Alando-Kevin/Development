import SwiftUI

extension Quality.Level {
    var color: Color {
        switch self {
        case .excellent, .good: return .green
        case .fair: return .orange
        case .poor, .offline: return .red
        case .unknown: return .secondary
        }
    }
}

/// Four bars, like the status bar signal icon, filled according to quality.
struct SignalBars: View {
    let bars: Int
    let color: Color
    var height: CGFloat = 56

    var body: some View {
        HStack(alignment: .bottom, spacing: height * 0.12) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: height * 0.07)
                    .fill(index < bars ? color : Color.secondary.opacity(0.22))
                    .frame(width: height * 0.2, height: height * (0.4 + 0.2 * CGFloat(index)))
            }
        }
        .frame(height: height, alignment: .bottom)
        .accessibilityLabel("\(bars) of 4 bars")
    }
}

/// A label above a value, used in rows of stats.
struct StatTile: View {
    let label: String
    let value: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Rounded card background used for grouped content.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

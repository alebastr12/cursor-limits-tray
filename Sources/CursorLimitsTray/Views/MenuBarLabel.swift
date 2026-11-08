import SwiftUI

/// Compact live title — SF Symbol + % for each connected provider.
struct MenuBarLabel: View {
    @ObservedObject var poller: UsagePoller

    var body: some View {
        HStack(spacing: 4) {
            if poller.menuBarSegments.isEmpty {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(poller.menuBarSegments.enumerated()), id: \.offset) { index, segment in
                    if index > 0 {
                        Text("·")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 2) {
                        Image(systemName: segment.provider.symbolName)
                            .font(.system(size: 10, weight: .semibold))
                        Text("\(segment.remainingPercent)%")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(segment.severity.color)
                }
            }
        }
        .accessibilityLabel(
            poller.menuBarSegments.isEmpty
                ? "Tray AI limits"
                : poller.menuBarSegments.map {
                    "\($0.provider.accessibilityName) \($0.remainingPercent)%"
                }.joined(separator: ", ")
        )
    }
}

import SwiftUI

/// Compact live title — only segments present in `menuBarText` (connected + live %).
struct MenuBarLabel: View {
    @ObservedObject var poller: UsagePoller

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(overallColor)

            if !poller.menuBarText.isEmpty {
                Text(poller.menuBarText)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(overallColor)
            }
        }
        .accessibilityLabel(poller.menuBarText.isEmpty ? "Лимиты" : poller.menuBarText)
    }

    private var overallColor: Color {
        let ranks: [LimitSeverity] = [.critical, .low, .ok]
        for s in ranks {
            if poller.cursorSeverity == s || poller.chatGPTSeverity == s || poller.claudeSeverity == s {
                return s.color
            }
        }
        return .secondary
    }
}

import SwiftUI

/// Compact live title for the menu-bar / notch area.
struct MenuBarLabel: View {
    @ObservedObject var poller: UsagePoller

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(overallColor)

            HStack(spacing: 0) {
                Text("C")
                    .foregroundStyle(poller.cursorSeverity.color)
                Text(cursorValue)
                    .foregroundStyle(poller.cursorSeverity.color)
                Text(" · ")
                    .foregroundStyle(.secondary)
                Text("G")
                    .foregroundStyle(poller.chatGPTSeverity.color)
                Text(chatValue)
                    .foregroundStyle(poller.chatGPTSeverity.color)
                if poller.claudeConfigured {
                    Text(" · ")
                        .foregroundStyle(.secondary)
                    Text("A")
                        .foregroundStyle(poller.claudeSeverity.color)
                    Text(claudeValue)
                        .foregroundStyle(poller.claudeSeverity.color)
                }
            }
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
        .accessibilityLabel(poller.menuBarText)
    }

    private var cursorValue: String {
        token(after: "C", in: poller.menuBarText)
    }

    private var chatValue: String {
        token(after: "G", in: poller.menuBarText)
    }

    private var claudeValue: String {
        token(after: "A", in: poller.menuBarText)
    }

    private func token(after letter: Character, in text: String) -> String {
        guard let idx = text.firstIndex(of: letter) else { return "—" }
        let rest = text[text.index(after: idx)...]
        let end = rest.firstIndex(of: " ") ?? rest.endIndex
        return String(rest[..<end])
    }

    private var overallColor: Color {
        let ranks: [LimitSeverity] = [.critical, .low, .ok, .unknown]
        for s in ranks {
            if poller.cursorSeverity == s || poller.chatGPTSeverity == s { return s.color }
            if poller.claudeConfigured, poller.claudeSeverity == s { return s.color }
        }
        return .secondary
    }
}

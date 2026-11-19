import Foundation

/// Builds the compact menu-bar model from a snapshot. No UI state here.
enum MenuBarPresenter {
    struct Output {
        var segments: [MenuBarSegment]
        var cursorSeverity: LimitSeverity
        var chatGPTSeverity: LimitSeverity
        var claudeSeverity: LimitSeverity
        var openCodeGoSeverity: LimitSeverity
    }

    static func make(
        snapshot: UsageSnapshot,
        cursorConnected: Bool,
        chatGPTConnected: Bool,
        claudeConnected: Bool,
        openCodeGoConnected: Bool
    ) -> Output {
        var segments: [MenuBarSegment] = []

        func append(_ provider: MenuBarSegment.Provider, _ providerSnapshot: ProviderSnapshot, isConnected: Bool) -> LimitSeverity {
            guard isConnected else { return .unknown }
            let meters = remainingMeters(from: providerSnapshot)
            for meter in meters {
                segments.append(MenuBarSegment(
                    provider: provider,
                    remainingPercent: Int(meter.remaining.rounded()),
                    severity: severity(remaining: meter.remaining, connected: true),
                    kindLabel: LimitKindLabel.tooltipLabel(forRowTitle: meter.title)
                ))
            }
            return severity(remaining: meters.map(\.remaining).min(), connected: !meters.isEmpty)
        }

        let cursor = append(.cursor, snapshot.cursor, isConnected: cursorConnected)
        let chatGPT = append(.chatGPT, snapshot.chatGPT, isConnected: chatGPTConnected)
        let claude = append(.claude, snapshot.claude, isConnected: claudeConnected)
        let openCodeGo = append(.openCodeGo, snapshot.openCodeGo, isConnected: openCodeGoConnected)

        return Output(
            segments: segments,
            cursorSeverity: cursor,
            chatGPTSeverity: chatGPT,
            claudeSeverity: claude,
            openCodeGoSeverity: openCodeGo
        )
    }

    /// Hover tip text: provider headers + kind/remaining lines (connected only).
    static func tooltip(segments: [MenuBarSegment]) -> String {
        guard !segments.isEmpty else { return L10n.tr("tooltip.empty") }
        var lines: [String] = []
        var lastProvider: MenuBarSegment.Provider?
        for segment in segments {
            if lastProvider != segment.provider {
                lines.append(segment.provider.accessibilityName)
                lastProvider = segment.provider
            }
            lines.append(L10n.tr("tooltip.line", segment.kindLabel, segment.remainingPercent))
        }
        return lines.joined(separator: "\n")
    }

    /// Compact plain text: `79% 88% · 67% 88%` (space within provider, · between).
    static func plainText(segments: [MenuBarSegment]) -> String {
        var parts: [String] = []
        var current: [String] = []
        var lastProvider: MenuBarSegment.Provider?
        for segment in segments {
            if let last = lastProvider, last != segment.provider {
                parts.append(current.joined(separator: " "))
                current = []
            }
            current.append("\(segment.remainingPercent)%")
            lastProvider = segment.provider
        }
        if !current.isEmpty { parts.append(current.joined(separator: " ")) }
        return parts.joined(separator: " · ")
    }

    /// Every row with a usable % — remaining allowance (100 − used), clamped.
    private static func remainingMeters(from provider: ProviderSnapshot) -> [(title: String, remaining: Double)] {
        provider.rows.compactMap { row in
            guard let used = row.percentUsed else { return nil }
            return (row.title, max(0, min(100, 100 - used)))
        }
    }

    private static func severity(remaining: Double?, connected: Bool) -> LimitSeverity {
        guard connected, let remaining else { return .unknown }
        switch remaining {
        case ..<15: return .critical
        case ..<35: return .low
        default: return .ok
        }
    }
}

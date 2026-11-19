import SwiftUI
import AppKit

struct PopoverView: View {
    @ObservedObject var poller: UsagePoller
    @Environment(\.openWindow) private var openWindow

    private var anyVisible: Bool {
        poller.cursorVisible || poller.chatGPTVisible || poller.claudeVisible || poller.openCodeGoVisible
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.35)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if poller.snapshot.isDemo {
                        banner(L10n.tr("popover.demo_banner"), color: .orange)
                    }

                    if !anyVisible && !poller.snapshot.isDemo {
                        emptyState
                    }

                    if poller.cursorVisible {
                        ProviderSection(
                            provider: .cursor,
                            snapshot: poller.snapshot.cursor,
                            connected: poller.cursorConnected
                        )
                    }

                    if poller.chatGPTVisible {
                        ProviderSection(
                            provider: .chatGPT,
                            snapshot: poller.snapshot.chatGPT,
                            connected: poller.chatGPTConnected,
                            source: poller.chatGPTAutoSource,
                            onReconnect: poller.chatGPTNeedsReconnect ? { openSettingsWindow() } : nil
                        )
                    }

                    if poller.claudeVisible {
                        ProviderSection(
                            provider: .claude,
                            snapshot: poller.snapshot.claude,
                            connected: poller.claudeConnected
                        )
                    }

                    if poller.openCodeGoVisible {
                        ProviderSection(
                            provider: .openCodeGo,
                            snapshot: poller.snapshot.openCodeGo,
                            connected: poller.openCodeGoConnected,
                            source: poller.openCodeGoAutoSource
                        )
                    }
                }
                .padding(16)
            }
            Divider().opacity(0.35)
            footer
        }
        .frame(width: PopoverLayout.width, height: popoverHeight)
        .background(WindowBackground())
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onReceive(NotificationCenter.default.publisher(for: .limitsTrayOpenDebugWindow)) { _ in
            openWindow(id: "debug-popover")
        }
        .onAppear { poller.start() }
    }

    private var popoverHeight: CGFloat {
        PopoverLayout.height(forVisibleProviders: poller.visibleProviderCount)
    }

    /// Settings is a real window, not a sheet: a confirmation alert must not be
    /// covered by the tray panel.
    private func openSettingsWindow() {
        StatusItemController.shared.dismissPanel()
        TrayLifecycle.beginShowingWindow()
        SettingsWindowController.shared.show(poller: poller)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr("popover.empty_title"))
                .font(.headline)
            Text(L10n.tr("popover.empty_body"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(L10n.settingsEllipsis) { openSettingsWindow() }
                .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.appName)
                    .font(.system(.headline, design: .rounded))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if poller.isRefreshing {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var subtitle: String {
        let interval = Int(AppPreferences.pollIntervalSeconds)
        let dates = [
            poller.cursorVisible ? poller.snapshot.cursor.fetchedAt : nil,
            poller.chatGPTVisible ? poller.snapshot.chatGPT.fetchedAt : nil,
            poller.claudeVisible ? poller.snapshot.claude.fetchedAt : nil
        ].compactMap { $0 }
        if let t = dates.max() {
            let relative = L10n.relativeDateFormatter.localizedString(for: t, relativeTo: Date())
            return L10n.tr("popover.subtitle_updated", relative, interval)
        }
        return L10n.tr("popover.subtitle_poll", interval)
    }

    private func banner(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(color)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var footer: some View {
        HStack {
            Button(L10n.refresh) { poller.refreshNow() }
                .keyboardShortcut("r", modifiers: .command)
            Spacer()
            Button(L10n.settingsEllipsis) { openSettingsWindow() }
            Button(L10n.quit) { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
                .help(L10n.tr("popover.quit_help"))
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct ProviderSection: View {
    let provider: MenuBarSegment.Provider
    let snapshot: ProviderSnapshot
    var connected: Bool = false
    var source: String?
    var onReconnect: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                if let logo = ProviderIcon.template(for: provider) {
                    Image(nsImage: logo)
                        .resizable()
                        .renderingMode(.template)
                        .foregroundStyle(.primary)
                        .frame(width: 18, height: 18)
                        .padding(.top, 2)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.name)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                    if let fetchedAt = snapshot.fetchedAt {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            Text(L10n.tr(
                                "popover.provider_updated",
                                L10n.relativeDateFormatter.localizedString(
                                    for: fetchedAt,
                                    relativeTo: context.date
                                )
                            ))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                statusChip
            }

            if connected, let source, !source.isEmpty {
                Text(L10n.tr("popover.source", source))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let error = snapshot.error {
                VStack(alignment: .leading, spacing: 6) {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                    if !snapshot.rows.isEmpty {
                        Text(L10n.tr("popover.stale_data"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let onReconnect {
                        Button(L10n.tr("popover.reconnect"), action: onReconnect)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }

            ForEach(snapshot.rows) { row in
                LimitRowView(row: row)
            }
        }
    }

    private var statusChip: some View {
        let hasError = snapshot.error != nil
        let color: Color = hasError ? (connected ? .orange : .red) : (connected ? .green : .secondary)
        let text: String
        if connected && !hasError {
            text = L10n.connected
        } else if !snapshot.status.isEmpty {
            text = snapshot.status
        } else {
            text = L10n.noStatus
        }
        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
                .font(.caption)
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }
}

private struct LimitRowView: View {
    let row: LimitRow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(row.title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                if let remaining = row.remainingLabel {
                    Text(remaining)
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                }
            }
            Text(row.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let used = row.percentUsed {
                UsageBar(remainingPercent: max(0, min(100, 100 - used)))
            }
            if let reset = row.resetLabel {
                Text(reset)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Filled length = remaining allowance; shrinks trailing-edge (right → left).
/// Color follows remaining: green → yellow → red as the bar gets shorter.
struct UsageBar: View {
    let remainingPercent: Double

    var body: some View {
        GeometryReader { geo in
            let remaining = min(max(remainingPercent, 0), 100)
            let width = geo.size.width * CGFloat(remaining / 100)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(barColor(for: remaining))
                    .frame(width: remaining > 0 ? max(3, width) : 0, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 6)
    }

    private func barColor(for remaining: Double) -> Color {
        // Match tray severity thresholds (remaining %).
        switch remaining {
        case ..<15: return Color(red: 0.90, green: 0.28, blue: 0.28)
        case ..<35: return Color(red: 0.95, green: 0.62, blue: 0.18)
        default: return Color(red: 0.20, green: 0.72, blue: 0.40)
        }
    }
}

private struct WindowBackground: View {
    var body: some View {
        Color(nsColor: .windowBackgroundColor)
    }
}

import SwiftUI

struct PopoverView: View {
    @ObservedObject var poller: UsagePoller
    @State private var showSettings = false
    @Environment(\.openWindow) private var openWindow

    private var anyConnected: Bool {
        poller.cursorConnected || poller.chatGPTConnected || poller.claudeConnected
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

                    if !anyConnected && !poller.snapshot.isDemo {
                        emptyState
                    }

                    if poller.cursorConnected {
                        ProviderSection(
                            snapshot: poller.snapshot.cursor,
                            connected: true
                        )
                    }

                    if poller.chatGPTConnected {
                        ProviderSection(
                            snapshot: poller.snapshot.chatGPT,
                            connected: true
                        )
                    }

                    if poller.claudeConnected {
                        ProviderSection(
                            snapshot: poller.snapshot.claude,
                            connected: true
                        )
                    }
                }
                .padding(16)
            }
            Divider().opacity(0.35)
            footer
        }
        .frame(width: 360, height: popoverHeight)
        .background(WindowBackground())
        .sheet(isPresented: $showSettings) {
            SettingsView(poller: poller)
        }
        .onReceive(NotificationCenter.default.publisher(for: .limitsTrayOpenDebugWindow)) { _ in
            openWindow(id: "debug-popover")
        }
        .onAppear { poller.start() }
    }

    private var popoverHeight: CGFloat {
        let n = [poller.cursorConnected, poller.chatGPTConnected, poller.claudeConnected].filter { $0 }.count
        switch n {
        case 0: return 280
        case 1: return 360
        case 2: return 480
        default: return 560
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr("popover.empty_title"))
                .font(.headline)
            Text(L10n.tr("popover.empty_body"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(L10n.settingsEllipsis) { showSettings = true }
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
            poller.cursorConnected ? poller.snapshot.cursor.fetchedAt : nil,
            poller.chatGPTConnected ? poller.snapshot.chatGPT.fetchedAt : nil,
            poller.claudeConnected ? poller.snapshot.claude.fetchedAt : nil
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
            Button(L10n.settingsEllipsis) { showSettings = true }
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
    let snapshot: ProviderSnapshot
    var connected: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(snapshot.name)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                Spacer()
                statusChip
            }

            if let error = snapshot.error, snapshot.rows.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(snapshot.rows) { row in
                LimitRowView(row: row)
            }
        }
    }

    private var statusChip: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(connected ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 7, height: 7)
            Text(connected ? L10n.connected : (snapshot.status.isEmpty ? L10n.noStatus : snapshot.status))
                .font(.caption)
                .foregroundStyle(connected ? .green : .secondary)
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
            if let percent = row.percentUsed {
                UsageBar(percent: percent)
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

struct UsageBar: View {
    let percent: Double

    var body: some View {
        GeometryReader { geo in
            let clamped = min(max(percent, 0), 100)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(barColor(for: clamped))
                    .frame(width: max(4, geo.size.width * CGFloat(clamped / 100)))
            }
        }
        .frame(height: 6)
    }

    private func barColor(for percent: Double) -> Color {
        switch percent {
        case ..<70: return Color(red: 0.20, green: 0.72, blue: 0.40)
        case ..<90: return Color(red: 0.95, green: 0.62, blue: 0.18)
        default: return Color(red: 0.90, green: 0.28, blue: 0.28)
        }
    }
}

private struct WindowBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color.accentColor.opacity(0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

import SwiftUI

struct PopoverView: View {
    @ObservedObject var poller: UsagePoller
    @State private var showSettings = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.35)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if poller.snapshot.isDemo {
                        banner("Демо-данные. Выключите демо в Настройках для живых лимитов.", color: .orange)
                    }
                    if (poller.chatGPTNeedsFDA && !poller.chatGPTConnected)
                        || (poller.claudeNeedsFDA && !poller.claudeConnected) {
                        fdaBanner
                    }

                    ProviderSection(
                        snapshot: poller.snapshot.cursor,
                        connected: poller.cursorConnected
                    )

                    ProviderSection(
                        snapshot: poller.snapshot.chatGPT,
                        connected: poller.chatGPTConnected,
                        connectTitle: poller.chatGPTConnected ? nil : "Подключить ChatGPT",
                        onConnect: { openChatGPTConnect() }
                    )

                    ProviderSection(
                        snapshot: poller.snapshot.claude,
                        connected: poller.claudeConnected,
                        connectTitle: poller.claudeConnected ? nil : "Подключить Claude",
                        onConnect: { openClaudeConnect() }
                    )
                }
                .padding(16)
            }
            Divider().opacity(0.35)
            footer
        }
        .frame(width: 360, height: 560)
        .background(WindowBackground())
        .sheet(isPresented: $showSettings) {
            SettingsView(poller: poller)
        }
        .onReceive(NotificationCenter.default.publisher(for: .limitsTrayOpenDebugWindow)) { _ in
            openWindow(id: "debug-popover")
        }
        .onAppear { poller.start() }
    }

    private func openChatGPTConnect() {
        // Detached floating panel — survives MenuBarExtra popover dismiss.
        ChatGPTConnectController.shared.present { [poller] header in
            poller.saveChatGPTCookie(header)
        }
    }

    private func openClaudeConnect() {
        ClaudeConnectController.shared.present { [poller] header in
            poller.saveClaudeCookie(header)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Лимиты")
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
        if let t = poller.snapshot.cursor.fetchedAt
            ?? poller.snapshot.chatGPT.fetchedAt
            ?? poller.snapshot.claude.fetchedAt {
            let f = RelativeDateTimeFormatter()
            f.locale = Locale(identifier: "ru_RU")
            f.unitsStyle = .abbreviated
            return "Обновлено \(f.localizedString(for: t, relativeTo: Date())) · каждые \(interval) с"
        }
        return "Опрос каждые \(interval) с"
    }

    private var fdaBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Чтобы взять сессию из Chrome / Claude Desktop автоматически, разрешите Полный доступ к диску для этого приложения.")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Открыть настройки") { poller.openFullDiskAccessSettings() }
                if !poller.chatGPTConnected {
                    Button("ChatGPT") { openChatGPTConnect() }
                        .buttonStyle(.borderedProminent)
                }
                if !poller.claudeConnected {
                    Button("Claude") { openClaudeConnect() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
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
            Button("Обновить") { poller.refreshNow() }
                .keyboardShortcut("r", modifiers: .command)
            Spacer()
            Button("Настройки…") { showSettings = true }
            Button("Выйти") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
                .help("Полностью выйти из приложения. Закрытие окон (✕ / ⌘W) оставляет трей.")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct ProviderSection: View {
    let snapshot: ProviderSnapshot
    var connected: Bool = false
    var connectTitle: String? = nil
    var onConnect: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(snapshot.name)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                Spacer()
                statusChip
            }

            if let connectTitle, let onConnect {
                Button(connectTitle, action: onConnect)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
            }

            if let error = snapshot.error, snapshot.rows.isEmpty, connectTitle == nil {
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
            Text(connected ? "Подключено" : (snapshot.status.isEmpty ? "Нет" : snapshot.status))
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

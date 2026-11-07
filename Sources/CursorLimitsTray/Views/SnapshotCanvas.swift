import SwiftUI

/// Static view for PNG export (main popover).
struct SnapshotCanvas: View {
    let snapshot: UsageSnapshot
    var showConnectChatGPT: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Лимиты")
                        .font(.system(.headline, design: .rounded))
                    Text(snapshot.isDemo ? "Демо · каждые 45 с" : "Живые данные · каждые 45 с")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().opacity(0.35)

            VStack(alignment: .leading, spacing: 16) {
                if snapshot.isDemo {
                    Text("Демо-данные.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
                canvasProvider(snapshot.cursor, connected: !snapshot.cursor.rows.isEmpty)
                canvasProvider(
                    snapshot.chatGPT,
                    connected: !snapshot.chatGPT.rows.isEmpty,
                    showConnect: showConnectChatGPT && snapshot.chatGPT.rows.isEmpty
                )
            }
            .padding(16)

            Spacer(minLength: 0)
            Divider().opacity(0.35)
            HStack {
                Text("Обновить").foregroundStyle(.secondary)
                Spacer()
                Text("Настройки…").foregroundStyle(.secondary)
                Text("Выйти").foregroundStyle(.secondary)
            }
            .font(.body)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 360, height: 480)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color.accentColor.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func canvasProvider(_ snap: ProviderSnapshot, connected: Bool, showConnect: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(snap.name)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(connected ? Color.green : Color.secondary.opacity(0.5)).frame(width: 7, height: 7)
                    Text(connected ? "Подключено" : "Не подключено")
                        .font(.caption)
                        .foregroundStyle(connected ? .green : .secondary)
                }
            }
            if showConnect {
                Text("Подключить ChatGPT")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
            }
            if let error = snap.error, snap.rows.isEmpty, !showConnect {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            ForEach(snap.rows) { row in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(row.title).font(.subheadline.weight(.medium))
                        Spacer()
                        if let remaining = row.remainingLabel {
                            Text(remaining).font(.subheadline.monospacedDigit().weight(.semibold))
                        }
                    }
                    Text(row.detail).font(.caption).foregroundStyle(.secondary)
                    if let percent = row.percentUsed { UsageBar(percent: percent) }
                    if let reset = row.resetLabel {
                        Text(reset).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

struct SettingsSnapshotCanvas: View {
    var cursorOK: Bool
    var chatOK: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Настройки")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 12) {
                statusLine("Cursor", ok: cursorOK, detail: cursorOK ? "Автоматически с этого Mac" : "Войдите в Cursor")
                statusLine("ChatGPT", ok: chatOK, detail: chatOK ? "Подключено" : "Один вход в окне приложения")
                if !chatOK {
                    Text("Подключить ChatGPT")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
                    Text("Взять сессию из браузера")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(14)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))

            Text("Опрос · 45 с · Открывать при входе")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Вручную (если авто не сработало) ▸")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
            HStack {
                Text("Сбросить секреты").foregroundStyle(.secondary)
                Spacer()
                Text("Закрыть").foregroundStyle(.secondary)
                Text("Сохранить").fontWeight(.semibold)
            }
        }
        .padding(20)
        .frame(width: 480, height: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func statusLine(_ title: String, ok: Bool, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(ok ? Color.green : Color.orange).frame(width: 10, height: 10).padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(ok ? "OK" : "…").font(.caption.weight(.semibold)).foregroundStyle(ok ? .green : .secondary)
        }
    }
}

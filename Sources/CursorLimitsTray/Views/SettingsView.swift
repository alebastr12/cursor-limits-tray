import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var poller: UsagePoller
    @Environment(\.dismiss) private var dismiss

    @State private var pollSeconds: Double = AppPreferences.pollIntervalSeconds
    @State private var demoMode: Bool = AppPreferences.forceDemoMode
    @State private var openAtLogin: Bool = false
    @State private var showManual = false
    @State private var manualChatCookie = ""
    @State private var manualCursorCookie = ""
    @State private var statusMessage: String?
    @State private var statusIsError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Настройки")
                .font(.title2.weight(.semibold))

            // Connection status — primary surface
            VStack(alignment: .leading, spacing: 12) {
                connectionRow(
                    title: "Cursor",
                    ok: poller.cursorConnected,
                    detail: poller.cursorConnected
                        ? "Автоматически с этого Mac"
                        : "Войдите в приложение Cursor"
                )

                connectionRow(
                    title: "ChatGPT",
                    ok: poller.chatGPTConnected,
                    detail: chatDetail
                )

                if !poller.chatGPTConnected {
                    Button {
                        ChatGPTConnectController.shared.present { header in
                            poller.saveChatGPTCookie(header)
                            statusIsError = false
                            statusMessage = "ChatGPT подключён."
                        }
                    } label: {
                        Text("Подключить ChatGPT")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Взять сессию из браузера") {
                        Task {
                            let ok = await poller.connectChatGPTFromBrowserInteractive()
                            if ok {
                                statusIsError = false
                                statusMessage = "Готово: сессия найдена в браузере."
                            } else if poller.chatGPTNeedsFDA {
                                statusIsError = true
                                statusMessage = "Нужен Полный доступ к диску — или войдите кнопкой выше."
                            } else {
                                statusIsError = true
                                statusMessage = "В браузере нет сессии chatgpt.com. Войдите на сайте или нажмите «Подключить ChatGPT»."
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    if poller.chatGPTNeedsFDA {
                        Button("Открыть «Полный доступ к диску»") {
                            poller.openFullDiskAccessSettings()
                        }
                    }
                }
            }
            .padding(14)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))

            Form {
                Section("Опрос") {
                    HStack {
                        Text("Интервал")
                        Slider(value: $pollSeconds, in: 15...300, step: 15)
                        Text("\(Int(pollSeconds)) с")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                    Toggle("Демо-данные", isOn: $demoMode)
                    Toggle("Открывать при входе", isOn: $openAtLogin)
                }

                DisclosureGroup("Вручную (если авто не сработало)", isExpanded: $showManual) {
                    Text("Обычному пользователю это не нужно.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Cursor cookie `WorkosCursorSessionToken`")
                        .font(.caption)
                    SecureField("Только если Cursor не подключился сам", text: $manualCursorCookie)

                    Text("ChatGPT cookie `__Secure-next-auth.session-token`")
                        .font(.caption)
                    TextEditor(text: $manualChatCookie)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 56)
                }
            }
            .formStyle(.grouped)

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(statusIsError ? .red : .green)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Сбросить секреты") {
                    manualChatCookie = ""
                    manualCursorCookie = ""
                    poller.clearStoredSecrets()
                    statusIsError = false
                    statusMessage = "Секреты очищены. Cursor может остаться на авто-входе."
                }
                Spacer()
                Button("Закрыть") { dismiss() }
                Button("Сохранить") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480, height: 560)
        .onAppear {
            openAtLogin = SMAppService.mainApp.status == .enabled
            manualChatCookie = KeychainStore.load(.chatGPTSessionCookie) ?? ""
            manualCursorCookie = KeychainStore.load(.cursorSessionCookie) ?? ""
            Task { _ = await poller.autoConnectChatGPTIfNeeded() }
        }
    }

    private var chatDetail: String {
        if poller.chatGPTConnected {
            if let src = poller.chatGPTAutoSource {
                return "Сессия из \(src)"
            }
            return "Подключено"
        }
        return "Один вход в окне приложения"
    }

    private func connectionRow(title: String, ok: Bool, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(ok ? Color.green : Color.orange)
                .frame(width: 10, height: 10)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(ok ? "OK" : "…")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ok ? .green : .secondary)
        }
    }

    private func save() {
        AppPreferences.pollIntervalSeconds = pollSeconds
        AppPreferences.forceDemoMode = demoMode

        do {
            let c = manualCursorCookie.trimmingCharacters(in: .whitespacesAndNewlines)
            if c.isEmpty { KeychainStore.delete(.cursorSessionCookie) }
            else { try KeychainStore.save(c, account: .cursorSessionCookie) }

            let g = manualChatCookie.trimmingCharacters(in: .whitespacesAndNewlines)
            if g.isEmpty { KeychainStore.delete(.chatGPTSessionCookie) }
            else {
                try KeychainStore.save(g, account: .chatGPTSessionCookie)
            }
        } catch {
            statusIsError = true
            statusMessage = "Не сохранилось: \(error.localizedDescription)"
            return
        }

        do {
            if openAtLogin { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            statusIsError = true
            statusMessage = "Сохранено, но «при входе» не удалось: \(error.localizedDescription)"
            poller.restartTimer()
            poller.refreshNow()
            return
        }

        poller.restartTimer()
        poller.refreshNow()
        statusIsError = false
        statusMessage = "Сохранено."
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { dismiss() }
    }
}

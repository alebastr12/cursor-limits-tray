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
    @State private var manualClaudeCookie = ""
    @State private var statusMessage: String?
    @State private var statusIsError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Настройки")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 12) {
                connectionRow(
                    title: "Cursor",
                    ok: poller.cursorConnected,
                    detail: poller.cursorConnected
                        ? "Токен в Keychain приложения"
                        : "Нужен локальный Cursor (один Unlock при необходимости)"
                )

                if !poller.cursorConnected {
                    Button("Разрешить доступ к Cursor (1× Keychain)") {
                        Task {
                            let ok = await poller.connectCursorFromLocalInteractive()
                            statusIsError = !ok
                            statusMessage = ok
                                ? "Cursor подключён."
                                : "Не удалось прочитать Cursor Safe Storage. Войдите в приложение Cursor."
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

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
                        Text("Подключить ChatGPT (вход в окне — без Keychain)")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Взять из браузера (тихо → макс. 1 пароль)") {
                        Task {
                            let ok = await poller.connectChatGPTFromBrowserInteractive()
                            if ok {
                                statusIsError = false
                                statusMessage = "Готово: сессия ChatGPT найдена в браузере."
                            } else if poller.chatGPTNeedsFDA {
                                statusIsError = true
                                statusMessage = "Нужен Полный доступ к диску — или войдите кнопкой выше."
                            } else {
                                statusIsError = true
                                statusMessage = "Нет сессии / Keychain уже использован. Лучше «Подключить ChatGPT»."
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                connectionRow(
                    title: "Claude",
                    ok: poller.claudeConfigured && poller.claudeConnected,
                    detail: claudeDetail
                )

                Text("В трее и поповере — только подключённые сервисы с живым %. Подключение только здесь.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !poller.claudeConfigured || !poller.claudeConnected {
                    Button {
                        ClaudeConnectController.shared.present { header in
                            poller.saveClaudeCookie(header)
                            statusIsError = false
                            statusMessage = "Claude подключён — смотрите трей."
                        }
                    } label: {
                        Text("Подключить Claude (вход в окне — без Keychain)")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Взять из Desktop / браузера (макс. 1 пароль)") {
                        Task {
                            let ok = await poller.connectClaudeFromBrowserInteractive()
                            if ok {
                                statusIsError = false
                                statusMessage = "Готово: Claude найден."
                            } else if poller.claudeNeedsFDA {
                                statusIsError = true
                                statusMessage = "Нужен Полный доступ к диску — или войдите кнопкой выше."
                            } else {
                                statusIsError = true
                                statusMessage = "Нет sessionKey / бюджет Keychain исчерпан. Лучше вход в окне."
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                if (poller.chatGPTNeedsFDA && !poller.chatGPTConnected)
                    || (poller.claudeNeedsFDA && !poller.claudeConfigured) {
                    Button("Открыть «Полный доступ к диску»") {
                        poller.openFullDiskAccessSettings()
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
                        .frame(minHeight: 48)

                    Text("Claude cookie `sessionKey=…`")
                        .font(.caption)
                    TextEditor(text: $manualClaudeCookie)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 48)
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
                    manualClaudeCookie = ""
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
        .frame(width: 480, height: 640)
        .onAppear {
            openAtLogin = LoginItemBootstrap.prefersOpenAtLogin
            manualChatCookie = SessionSecrets.get(.chatGPTSessionCookie) ?? ""
            manualCursorCookie = SessionSecrets.get(.cursorSessionCookie) ?? ""
            manualClaudeCookie = SessionSecrets.get(.claudeSessionCookie) ?? ""
            // Do not re-scan browsers / Safe Storage just because Settings opened.
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

    private var claudeDetail: String {
        if poller.claudeConfigured {
            if let src = poller.claudeAutoSource {
                return "В трее · \(src)"
            }
            return poller.claudeConnected ? "В трее · подключено" : "В трее · нет связи"
        }
        return "Скрыт, пока не подключите"
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

        let c = manualCursorCookie.trimmingCharacters(in: .whitespacesAndNewlines)
        if c.isEmpty { SessionSecrets.clear(.cursorSessionCookie) }
        else { SessionSecrets.set(c, account: .cursorSessionCookie) }

        let g = manualChatCookie.trimmingCharacters(in: .whitespacesAndNewlines)
        if g.isEmpty { SessionSecrets.clear(.chatGPTSessionCookie) }
        else { SessionSecrets.set(g, account: .chatGPTSessionCookie) }

        let a = manualClaudeCookie.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.isEmpty { SessionSecrets.clear(.claudeSessionCookie) }
        else { SessionSecrets.set(a, account: .claudeSessionCookie) }

        LoginItemBootstrap.prefersOpenAtLogin = openAtLogin
        do {
            if openAtLogin {
                try SMAppService.mainApp.register()
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            statusIsError = true
            statusMessage = "Сохранено, но «при входе» не удалось: \(error.localizedDescription). Если запускаете с DMG — скопируйте в Программы."
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

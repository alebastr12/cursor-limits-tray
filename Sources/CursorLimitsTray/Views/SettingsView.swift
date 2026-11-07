import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var poller: UsagePoller
    @Environment(\.dismiss) private var dismiss

    @State private var pollSeconds: Double = AppPreferences.pollIntervalSeconds
    @State private var demoMode: Bool = AppPreferences.forceDemoMode
    @State private var openAtLogin: Bool = false
    @State private var showAdvanced = false
    @State private var manualChatCookie = ""
    @State private var manualCursorCookie = ""
    @State private var manualClaudeCookie = ""
    @State private var statusMessage: String?
    @State private var statusIsError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Настройки")
                .font(.title2.weight(.semibold))

            Text("Обычный путь — без паролей Keychain / SecurityAgent. Подключение через окно входа.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                connectionRow(
                    title: "Cursor",
                    ok: poller.cursorConnected,
                    detail: poller.cursorConnected
                        ? "Токен в Keychain приложения"
                        : "Нужен токен (см. Advanced) или войдите в Cursor на этом Mac и вставьте cookie"
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
                            statusMessage = "ChatGPT подключён (без Keychain)."
                        }
                    } label: {
                        Text("Подключить ChatGPT")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                connectionRow(
                    title: "Claude",
                    ok: poller.claudeConfigured && poller.claudeConnected,
                    detail: claudeDetail
                )

                if !poller.claudeConfigured || !poller.claudeConnected {
                    Button {
                        ClaudeConnectController.shared.present { header in
                            poller.saveClaudeCookie(header)
                            statusIsError = false
                            statusMessage = "Claude подключён (без Keychain)."
                        }
                    } label: {
                        Text("Подключить Claude")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
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

                DisclosureGroup("Advanced (может запросить пароль Keychain)", isExpanded: $showAdvanced) {
                    Text("Не нужно для обычной работы. Импорт из браузера / Cursor Safe Storage может показать диалог пароля.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Взять ChatGPT из браузера (может спросить пароль)") {
                        Task {
                            let ok = await poller.connectChatGPTFromBrowserInteractive()
                            statusIsError = !ok
                            statusMessage = ok
                                ? "ChatGPT из браузера."
                                : (poller.chatGPTNeedsFDA
                                    ? "Нужен Полный доступ к диску — или «Подключить ChatGPT» выше."
                                    : "Не вышло. Лучше вход в окне (без пароля).")
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Button("Взять Claude из Desktop / браузера (может спросить пароль)") {
                        Task {
                            let ok = await poller.connectClaudeFromBrowserInteractive()
                            statusIsError = !ok
                            statusMessage = ok
                                ? "Claude импортирован."
                                : "Не вышло. Лучше «Подключить Claude» выше (без пароля)."
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Button("Cursor Safe Storage (может спросить пароль)") {
                        Task {
                            let ok = await poller.connectCursorFromLocalInteractive()
                            statusIsError = !ok
                            statusMessage = ok
                                ? "Cursor из Safe Storage."
                                : "Нет доступа. Вставьте cookie ниже или войдите в Cursor."
                        }
                    }
                    .frame(maxWidth: .infinity)

                    if poller.chatGPTNeedsFDA || poller.claudeNeedsFDA {
                        Button("Открыть «Полный доступ к диску»") {
                            poller.openFullDiskAccessSettings()
                        }
                    }

                    Text("Вставка сессии вручную (без Keychain unlock)")
                        .font(.caption.weight(.semibold))
                        .padding(.top, 6)

                    Text("Cursor cookie `WorkosCursorSessionToken` или bearer")
                        .font(.caption)
                    SecureField("Вставьте значение", text: $manualCursorCookie)

                    Text("ChatGPT cookie")
                        .font(.caption)
                    TextEditor(text: $manualChatCookie)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 40)

                    Text("Claude `sessionKey=…`")
                        .font(.caption)
                    TextEditor(text: $manualClaudeCookie)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 40)
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
                    statusMessage = "Секреты очищены."
                }
                Spacer()
                Button("Закрыть") { dismiss() }
                Button("Сохранить") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 500, height: 620)
        .onAppear {
            openAtLogin = LoginItemBootstrap.prefersOpenAtLogin
            manualChatCookie = SessionSecrets.get(.chatGPTSessionCookie) ?? ""
            manualCursorCookie = SessionSecrets.get(.cursorSessionCookie)
                ?? SessionSecrets.get(.cursorBearerOverride)
                ?? ""
            manualClaudeCookie = SessionSecrets.get(.claudeSessionCookie) ?? ""
        }
    }

    private var chatDetail: String {
        if poller.chatGPTConnected { return "Подключено (окно входа)" }
        return "Подключить в окне — без пароля"
    }

    private var claudeDetail: String {
        if poller.claudeConfigured {
            return poller.claudeConnected ? "В трее · подключено" : "В трее · нет связи"
        }
        return "Подключить в окне — без пароля"
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
        if c.isEmpty {
            SessionSecrets.clear(.cursorSessionCookie)
            // Keep bearer unless user cleared everything via reset — only clear session cookie field.
        } else if c.lowercased().hasPrefix("eyj") || c.count > 80 && !c.contains("=") {
            SessionSecrets.set(c, account: .cursorBearerOverride)
        } else {
            SessionSecrets.set(c, account: .cursorSessionCookie)
        }

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
            statusMessage = "Сохранено, но login item: \(error.localizedDescription). Скопируйте .app в Программы."
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

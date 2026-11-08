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
            Text(L10n.settings)
                .font(.title2.weight(.semibold))

            Text(L10n.tr("settings.blurb"))
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                connectionRow(
                    title: "Cursor",
                    ok: poller.cursorConnected,
                    detail: poller.cursorConnected
                        ? L10n.tr("settings.cursor_ok")
                        : L10n.tr("settings.cursor_need")
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
                            manualChatCookie = header
                            statusIsError = false
                            statusMessage = L10n.tr("settings.msg_chatgpt_connected")
                        }
                    } label: {
                        Text(L10n.tr("settings.connect_chatgpt"))
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
                            manualClaudeCookie = header
                            statusIsError = false
                            statusMessage = L10n.tr("settings.msg_claude_connected")
                        }
                    } label: {
                        Text(L10n.tr("settings.connect_claude"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(14)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))

            Form {
                Section(L10n.tr("settings.polling")) {
                    HStack {
                        Text(L10n.tr("settings.interval"))
                        Slider(value: $pollSeconds, in: 15...300, step: 15)
                        Text(L10n.tr("settings.seconds_short", Int(pollSeconds)))
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                    Toggle(L10n.tr("settings.demo"), isOn: $demoMode)
                    Toggle(L10n.tr("settings.open_at_login"), isOn: $openAtLogin)
                }

                DisclosureGroup(L10n.tr("settings.advanced"), isExpanded: $showAdvanced) {
                    Text(L10n.tr("settings.advanced_blurb"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button(L10n.tr("settings.import_chatgpt_browser")) {
                        Task {
                            let ok = await poller.connectChatGPTFromBrowserInteractive()
                            statusIsError = !ok
                            statusMessage = ok
                                ? L10n.tr("settings.msg_chatgpt_browser_ok")
                                : (poller.chatGPTNeedsFDA
                                    ? L10n.tr("settings.msg_chatgpt_browser_fda")
                                    : L10n.tr("settings.msg_chatgpt_browser_fail"))
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Button(L10n.tr("settings.import_claude_browser")) {
                        Task {
                            let ok = await poller.connectClaudeFromBrowserInteractive()
                            statusIsError = !ok
                            statusMessage = ok
                                ? L10n.tr("settings.msg_claude_browser_ok")
                                : L10n.tr("settings.msg_claude_browser_fail")
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Button(L10n.tr("settings.import_cursor_safe")) {
                        Task {
                            let ok = await poller.connectCursorFromLocalInteractive()
                            statusIsError = !ok
                            statusMessage = ok
                                ? L10n.tr("settings.msg_cursor_ok")
                                : L10n.tr("settings.msg_cursor_fail")
                        }
                    }
                    .frame(maxWidth: .infinity)

                    if poller.chatGPTNeedsFDA || poller.claudeNeedsFDA {
                        Button(L10n.tr("settings.open_fda")) {
                            poller.openFullDiskAccessSettings()
                        }
                    }

                    Text(L10n.tr("settings.manual_title"))
                        .font(.caption.weight(.semibold))
                        .padding(.top, 6)

                    Text(L10n.tr("settings.cursor_cookie_hint"))
                        .font(.caption)
                    SecureField(L10n.tr("settings.paste_value"), text: $manualCursorCookie)

                    Text(L10n.tr("settings.chatgpt_cookie"))
                        .font(.caption)
                    TextEditor(text: $manualChatCookie)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 40)

                    Text(L10n.tr("settings.claude_cookie"))
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
                Button(L10n.tr("settings.reset_secrets")) {
                    manualChatCookie = ""
                    manualCursorCookie = ""
                    manualClaudeCookie = ""
                    poller.clearStoredSecrets()
                    statusIsError = false
                    statusMessage = L10n.tr("settings.msg_secrets_cleared")
                }
                Spacer()
                Button(L10n.close) { dismiss() }
                Button(L10n.save) { save() }
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
        if poller.chatGPTConnected { return L10n.tr("settings.chatgpt_ok") }
        return L10n.tr("settings.chatgpt_need")
    }

    private var claudeDetail: String {
        if poller.claudeConfigured {
            return poller.claudeConnected ? L10n.tr("settings.claude_ok") : L10n.tr("settings.claude_bad")
        }
        return L10n.tr("settings.claude_need")
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
            Text(ok ? L10n.ok : "…")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ok ? .green : .secondary)
        }
    }

    private func save() {
        AppPreferences.pollIntervalSeconds = pollSeconds
        AppPreferences.forceDemoMode = demoMode

        let c = manualCursorCookie.trimmingCharacters(in: .whitespacesAndNewlines)
        if !c.isEmpty {
            if c.lowercased().hasPrefix("eyj") || (c.count > 80 && !c.contains("=")) {
                SessionSecrets.set(c, account: .cursorBearerOverride)
            } else {
                SessionSecrets.set(c, account: .cursorSessionCookie)
            }
        }

        let g = manualChatCookie.trimmingCharacters(in: .whitespacesAndNewlines)
        if !g.isEmpty {
            SessionSecrets.set(g, account: .chatGPTSessionCookie)
        }

        let a = manualClaudeCookie.trimmingCharacters(in: .whitespacesAndNewlines)
        if !a.isEmpty {
            SessionSecrets.set(a, account: .claudeSessionCookie)
        }

        LoginItemBootstrap.prefersOpenAtLogin = openAtLogin
        LoginItemBootstrap.syncLoginItemWithPreference(quiet: false)
        if openAtLogin, SMAppService.mainApp.status != .enabled,
           !Bundle.main.bundlePath.hasPrefix("/Volumes/") {
            statusIsError = true
            statusMessage = L10n.tr("settings.msg_login_item_fail")
            poller.restartTimer()
            poller.refreshNow()
            return
        }

        poller.restartTimer()
        poller.refreshNow()
        statusIsError = false
        statusMessage = L10n.tr("settings.msg_saved")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { dismiss() }
    }
}

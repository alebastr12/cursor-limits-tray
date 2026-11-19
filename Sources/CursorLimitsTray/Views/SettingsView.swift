import SwiftUI
import AppKit
import ServiceManagement

private enum SettingsProvider {
    case cursor
    case chatGPT
    case claude
    case openCodeGo

    var name: String {
        switch self {
        case .cursor: return "Cursor"
        case .chatGPT: return "ChatGPT"
        case .claude: return "Claude"
        case .openCodeGo: return "OpenCode Go"
        }
    }

    @MainActor
    func remove(from poller: UsagePoller) {
        switch self {
        case .cursor: poller.forgetCursor()
        case .chatGPT: poller.forgetChatGPT()
        case .claude: poller.forgetClaude()
        case .openCodeGo: poller.forgetOpenCodeGo()
        }
    }
}

struct SettingsView: View {
    @ObservedObject var poller: UsagePoller

    @State private var pollSeconds: Double = AppPreferences.pollIntervalSeconds
    @State private var demoMode: Bool = AppPreferences.forceDemoMode
    @State private var openAtLogin: Bool = false
    @State private var showAdvanced = false
    @State private var showSecrets = false
    @State private var hasLegacyCursor = false
    @State private var providerToRemove: SettingsProvider?
    @State private var manualChatCookie = ""
    @State private var manualCursorCookie = ""
    @State private var manualClaudeCookie = ""
    @State private var manualOpenCodeKey = ""
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
                        : L10n.tr("settings.cursor_need"),
                    onRemove: (poller.cursorConnected || poller.cursorConfigured || hasLegacyCursor)
                        ? { requestRemove(.cursor) }
                        : nil
                )

                if hasLegacyCursor {
                    Button {
                        let ok = SessionSecrets.importLegacyCursorTokenInteractively()
                        hasLegacyCursor = SessionSecrets.hasLegacyCursorToken
                        poller.refreshNow()
                        statusIsError = !ok
                        statusMessage = ok
                            ? L10n.tr("settings.msg_cursor_migrated")
                            : L10n.tr("settings.msg_cursor_migrate_failed")
                    } label: {
                        Text(L10n.tr("settings.legacy_cursor_title"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Text(L10n.tr("settings.legacy_cursor_hint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                connectionRow(
                    title: "ChatGPT",
                    ok: poller.chatGPTConnected,
                    detail: chatDetail,
                    onRemove: poller.chatGPTConfigured ? { requestRemove(.chatGPT) } : nil
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

                    if let error = poller.snapshot.chatGPT.error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                connectionRow(
                    title: "Claude",
                    ok: poller.claudeConfigured && poller.claudeConnected,
                    detail: claudeDetail,
                    onRemove: poller.claudeConfigured ? { requestRemove(.claude) } : nil
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

                if poller.claudeConfigured, let error = poller.snapshot.claude.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                connectionRow(
                    title: "OpenCode Go",
                    ok: poller.openCodeGoConnected,
                    detail: openCodeGoDetail,
                    onRemove: poller.openCodeGoConfigured ? { requestRemove(.openCodeGo) } : nil
                )

                if !poller.openCodeGoConfigured {
                    Button {
                        poller.connectOpenCodeGo()
                        statusIsError = false
                        statusMessage = L10n.tr("settings.msg_opencode_connecting")
                    } label: {
                        Text(L10n.tr("settings.connect_opencode"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                if poller.openCodeGoConfigured, let error = poller.snapshot.openCodeGo.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
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
                    secretField(L10n.tr("settings.paste_value"), text: $manualCursorCookie)

                    secretField(L10n.tr("settings.chatgpt_cookie"), text: $manualChatCookie)
                    secretField(L10n.tr("settings.claude_cookie"), text: $manualClaudeCookie)

                    Text(L10n.tr("settings.opencode_key"))
                        .font(.caption)
                    secretField(L10n.tr("settings.paste_value"), text: $manualOpenCodeKey)
                    Text(L10n.tr("settings.opencode_key_hint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
                Button(L10n.close) { closeSettingsWindow() }
                Button(L10n.save) { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 500, height: 720)
        .alert(
            providerToRemove.map { L10n.tr("settings.remove_title", $0.name) } ?? "",
            isPresented: removalAlertPresented,
            presenting: providerToRemove
        ) { provider in
            Button(L10n.tr("settings.remove_action"), role: .destructive) {
                performRemove(provider)
            }
            Button(L10n.tr("common.cancel"), role: .cancel) {
                providerToRemove = nil
                StatusItemController.shared.isModalPresented = false
            }
        } message: { provider in
            Text(L10n.tr("settings.remove_message", provider.name))
        }
        .onAppear {
            openAtLogin = LoginItemBootstrap.prefersOpenAtLogin
            hasLegacyCursor = SessionSecrets.hasLegacyCursorToken
            manualChatCookie = SessionSecrets.get(.chatGPTSessionCookie) ?? ""
            manualCursorCookie = SessionSecrets.get(.cursorSessionCookie)
                ?? SessionSecrets.get(.cursorBearerOverride)
                ?? ""
            manualClaudeCookie = SessionSecrets.get(.claudeSessionCookie) ?? ""
            manualOpenCodeKey = SessionSecrets.get(.openCodeGoAPIKey) ?? ""
        }
    }

    private var openCodeGoDetail: String {
        if poller.openCodeGoConnected {
            if let source = poller.openCodeGoAutoSource, !source.isEmpty {
                return L10n.tr("settings.opencode_ok_source", source)
            }
            return L10n.tr("settings.opencode_ok")
        }
        if poller.openCodeGoConfigured { return L10n.tr("settings.opencode_bad") }
        return L10n.tr("settings.opencode_need")
    }

    private var chatDetail: String {
        if poller.chatGPTConnected {
            if let source = poller.chatGPTAutoSource, !source.isEmpty {
                return L10n.tr("settings.chatgpt_source", source)
            }
            return L10n.tr("settings.chatgpt_ok")
        }
        if poller.chatGPTNeedsReconnect { return L10n.tr("settings.chatgpt_reconnect") }
        return L10n.tr("settings.chatgpt_need")
    }

    private var claudeDetail: String {
        if poller.claudeConfigured {
            return poller.claudeConnected ? L10n.tr("settings.claude_ok") : L10n.tr("settings.claude_bad")
        }
        return L10n.tr("settings.claude_need")
    }

    private func connectionRow(
        title: String,
        ok: Bool,
        detail: String,
        onRemove: (() -> Void)? = nil
    ) -> some View {
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
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(ok ? L10n.ok : "…")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ok ? .green : .secondary)
                .padding(.top, 2)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help(L10n.tr("settings.remove_help", title))
                .accessibilityLabel(L10n.tr("settings.remove_help", title))
            }
        }
    }

    private func closeSettingsWindow() {
        NSApp.windows
            .first(where: { $0.isVisible && TrayLifecycle.isSettingsLikeWindow($0) })?
            .close()
    }

    private var removalAlertPresented: Binding<Bool> {
        Binding(
            get: { providerToRemove != nil },
            set: { presented in
                if !presented {
                    providerToRemove = nil
                    StatusItemController.shared.isModalPresented = false
                }
            }
        )
    }

    private func requestRemove(_ provider: SettingsProvider) {
        StatusItemController.shared.isModalPresented = true
        providerToRemove = provider
    }

    private func performRemove(_ provider: SettingsProvider) {
        provider.remove(from: poller)
        statusIsError = false
        switch provider {
        case .cursor:
            manualCursorCookie = ""
            hasLegacyCursor = SessionSecrets.hasLegacyCursorToken
            statusMessage = L10n.tr("settings.msg_cursor_disconnected")
        case .chatGPT:
            manualChatCookie = ""
            statusMessage = L10n.tr("settings.msg_chatgpt_disconnected")
        case .claude:
            manualClaudeCookie = ""
            statusMessage = L10n.tr("settings.msg_claude_disconnected")
        case .openCodeGo:
            manualOpenCodeKey = ""
            statusMessage = L10n.tr("settings.msg_opencode_disconnected")
        }
        providerToRemove = nil
        StatusItemController.shared.isModalPresented = false
    }

    private func secretField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption)
                Spacer()
                Button(showSecrets ? L10n.tr("settings.hide_secrets") : L10n.tr("settings.show_secrets")) {
                    showSecrets.toggle()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            Group {
                if showSecrets {
                    TextField(L10n.tr("settings.paste_value"), text: text, axis: .vertical)
                        .lineLimit(2...4)
                } else {
                    SecureField(L10n.tr("settings.paste_value"), text: text)
                }
            }
            .textFieldStyle(.roundedBorder)
            .font(.system(.caption, design: .monospaced))
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

        let o = manualOpenCodeKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !o.isEmpty {
            poller.saveOpenCodeGoKey(o)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { closeSettingsWindow() }
    }
}

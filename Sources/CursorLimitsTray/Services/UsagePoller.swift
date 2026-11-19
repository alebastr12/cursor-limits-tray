import Foundation
import Combine
import AppKit

@MainActor
final class UsagePoller: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot = .empty
    @Published private(set) var isRefreshing = false
    @Published var lastError: String?

    @Published private(set) var cursorConnected = false
    @Published private(set) var cursorConfigured = false
    @Published private(set) var chatGPTConnected = false
    @Published private(set) var claudeConnected = false
    @Published private(set) var openCodeGoConnected = false
    /// True when ChatGPT has credentials (app Keychain or recoverable WebKit session),
    /// even if the last fetch failed. Keeps the section visible with its error.
    @Published private(set) var chatGPTConfigured = false
    /// Server rejected the ChatGPT web session — user must reconnect.
    @Published private(set) var chatGPTNeedsReconnect = false
    /// True after user connected Claude (secrets in app Keychain). Hidden from tray/popover until then.
    @Published private(set) var claudeConfigured = false
    /// True when a manual Go key or the local OpenCode credential is available.
    @Published private(set) var openCodeGoConfigured = false
    /// Compact menu-bar: one segment per live % (all limits of connected providers). Empty if none.
    @Published private(set) var menuBarSegments: [MenuBarSegment] = []
    /// Accessibility / legacy plain text (e.g. `79% 56% · 67% 88%`).
    @Published private(set) var menuBarText: String = ""
    @Published private(set) var cursorSeverity: LimitSeverity = .unknown
    @Published private(set) var chatGPTSeverity: LimitSeverity = .unknown
    @Published private(set) var claudeSeverity: LimitSeverity = .unknown
    @Published private(set) var openCodeGoSeverity: LimitSeverity = .unknown
    /// First configured provider whose last refresh failed — drives the tray warning icon.
    @Published private(set) var providerWarning: String?
    /// Number of provider sections currently visible (drives popover/panel height).
    @Published private(set) var visibleProviderCount = 0

    var cursorVisible: Bool {
        ProviderActivity.isVisible(id: .cursor, connected: cursorConnected, snapshot: snapshot.cursor)
    }

    var chatGPTVisible: Bool {
        ProviderActivity.isVisible(id: .chatGPT, connected: chatGPTConnected, snapshot: snapshot.chatGPT)
    }

    var claudeVisible: Bool {
        ProviderActivity.isVisible(id: .claude, connected: claudeConnected, snapshot: snapshot.claude)
    }

    var openCodeGoVisible: Bool {
        ProviderActivity.isVisible(id: .openCodeGo, connected: openCodeGoConnected, snapshot: snapshot.openCodeGo)
    }
    @Published var chatGPTNeedsFDA = false
    @Published var claudeNeedsFDA = false
    @Published var chatGPTAutoSource: String?
    @Published var claudeAutoSource: String?
    @Published var openCodeGoAutoSource: String?
    @Published var connectionNote: String?

    func applyDemoSnapshot() {
        snapshot = .demo
        lastError = nil
        cursorConnected = true
        cursorConfigured = true
        chatGPTConnected = true
        chatGPTConfigured = true
        chatGPTNeedsReconnect = false
        chatGPTAutoSource = nil
        claudeConnected = true
        claudeConfigured = true
        openCodeGoConnected = true
        openCodeGoConfigured = true
        openCodeGoAutoSource = nil
        providerWarning = nil
        publishMenuBar()
    }

    private var timer: Timer?
    private var inFlight: Task<Void, Never>?
    private var didStart = false
    private var startObserver: NSObjectProtocol?
    /// Only the newest refresh may publish results.
    private var refreshGeneration = 0
    /// After an auth failure, skip the doomed web-session exchange for a while.
    private var chatGPTAuthFailedAt: Date?
    private static let recoveryDisabledKey = "chatgpt.recoveryDisabled"
    /// Set by "Reset Secrets" so the WebKit cookie store cannot silently undo it.
    /// Persisted: a relaunch must not resurrect a session the user cleared.
    private var chatGPTRecoveryDisabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.recoveryDisabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.recoveryDisabledKey) }
    }
    private static let openCodeGoDisabledKey = "opencodego.autoDisabled"
    /// Set by "Disconnect OpenCode Go" so the local OpenCode login is not
    /// re-imported until the user explicitly reconnects it.
    private var openCodeGoAutoDisabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.openCodeGoDisabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.openCodeGoDisabledKey) }
    }

    init() {
        startObserver = NotificationCenter.default.addObserver(
            forName: .limitsTrayShouldStart,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.start() }
        }
    }

    deinit {
        if let startObserver {
            NotificationCenter.default.removeObserver(startObserver)
        }
    }

    func start() {
        guard !didStart else {
            refreshNow()
            return
        }
        didStart = true
        if ProcessInfo.processInfo.arguments.contains("--connect-chatgpt")
            || ProcessInfo.processInfo.arguments.contains("--connect-claude") {
            restartTimer()
            return
        }
        Task {
            // Launch: app Keychain / memory ONLY — zero foreign Safe Storage (zero SecurityAgent).
            _ = SessionSecrets.cursorAuth()
            refreshConfiguredFlags()
            await refresh()
        }
        restartTimer()
    }

    private var hasChatGPTSecrets: Bool {
        SessionSecrets.get(.chatGPTSessionCookie) != nil
            || SessionSecrets.get(.chatGPTBearerOverride) != nil
    }

    private func refreshConfiguredFlags() {
        claudeConfigured = SessionSecrets.get(.claudeSessionCookie) != nil
            || SessionSecrets.get(.claudeBearerOverride) != nil
        if !claudeConfigured {
            claudeConnected = false
        }
        chatGPTConfigured = hasChatGPTSecrets
        if !chatGPTConfigured {
            chatGPTConnected = false
        }
    }

    func restartTimer() {
        timer?.invalidate()
        let interval = AppPreferences.pollIntervalSeconds
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshNow() }
        }
    }

    func refreshNow() {
        // Manual refresh: retry the web session even if it failed recently.
        chatGPTAuthFailedAt = nil
        refreshGeneration &+= 1
        let generation = refreshGeneration
        inFlight?.cancel()
        inFlight = Task { await refresh(generation: generation) }
    }

    /// Snapshot/helper: app secrets only — never browser Safe Storage.
    @discardableResult
    func autoConnectChatGPTIfNeeded() async -> Bool {
        if SessionSecrets.get(.chatGPTSessionCookie) != nil || SessionSecrets.get(.chatGPTBearerOverride) != nil {
            chatGPTConnected = true
            return true
        }
        return false
    }

    @discardableResult
    func autoConnectClaudeIfNeeded() async -> Bool {
        if SessionSecrets.get(.claudeSessionCookie) != nil || SessionSecrets.get(.claudeBearerOverride) != nil {
            claudeConfigured = true
            claudeConnected = true
            return true
        }
        return false
    }

    /// «Взять сессию из браузера» — Advanced only; may unlock Keychain once.
    @discardableResult
    func connectChatGPTFromBrowserInteractive() async -> Bool {
        ForeignKeychainGate.withForeignAccessAllowed {
            switch BrowserCookieReader.findChatGPTSessionCookie(allowKeychainPrompt: true) {
            case .found(let header, let source):
                SessionSecrets.set(header, account: .chatGPTSessionCookie)
                chatGPTAutoSource = source
                chatGPTNeedsFDA = false
                chatGPTConfigured = true
                chatGPTConnected = true
                chatGPTNeedsReconnect = false
                chatGPTAuthFailedAt = nil
                chatGPTRecoveryDisabled = false
                refreshNow()
                return true
            case .needsFullDiskAccess:
                chatGPTNeedsFDA = true
                return false
            case .notFound, .error:
                return false
            }
        }
    }

    @discardableResult
    func connectClaudeFromBrowserInteractive() async -> Bool {
        ForeignKeychainGate.withForeignAccessAllowed {
            if let local = ClaudeLocalAuth.loadWithSingleUnlock() {
                if let cookie = local.sessionCookie {
                    SessionSecrets.set(cookie, account: .claudeSessionCookie)
                }
                if let oauth = local.oauthAccessToken {
                    SessionSecrets.set(oauth, account: .claudeBearerOverride)
                }
                claudeAutoSource = local.source
                claudeConfigured = true
                claudeConnected = true
                claudeNeedsFDA = false
                refreshNow()
                return true
            }
            return false
        }
    }

    /// Advanced only — may prompt Keychain.
    @discardableResult
    func connectCursorFromLocalInteractive() async -> Bool {
        if let creds = SessionSecrets.importCursorFromSafeStorageInteractive() {
            cursorConnected = true
            cursorConfigured = true
            connectionNote = L10n.tr("poller.note_cursor_local")
            _ = creds
            refreshNow()
            return true
        }
        return false
    }

    func saveChatGPTCookie(_ header: String) {
        SessionSecrets.set(header, account: .chatGPTSessionCookie)
        chatGPTAuthFailedAt = nil
        chatGPTRecoveryDisabled = false
        chatGPTNeedsReconnect = false
        chatGPTAutoSource = nil
        // Optimistic UI: keep connected while refresh fetches rows.
        chatGPTConfigured = SessionSecrets.get(.chatGPTSessionCookie) != nil
        chatGPTConnected = chatGPTConfigured
        chatGPTNeedsFDA = false
        connectionNote = L10n.tr("poller.note_chatgpt")
        refreshNow()
    }

    func saveClaudeCookie(_ header: String) {
        SessionSecrets.set(header, account: .claudeSessionCookie)
        claudeConfigured = SessionSecrets.get(.claudeSessionCookie) != nil
            || SessionSecrets.get(.claudeBearerOverride) != nil
        claudeConnected = claudeConfigured
        claudeNeedsFDA = false
        connectionNote = L10n.tr("poller.note_claude")
        refreshNow()
    }

    func clearStoredSecrets() {
        SessionSecrets.clearAll()
        cursorConnected = false
        cursorConfigured = false
        chatGPTConnected = false
        chatGPTConfigured = false
        chatGPTNeedsReconnect = false
        chatGPTAuthFailedAt = nil
        chatGPTRecoveryDisabled = true
        Task { await WebKitCookieBridge.clearChatGPTCookies() }
        claudeConnected = false
        claudeConfigured = false
        openCodeGoConnected = false
        openCodeGoConfigured = false
        openCodeGoAutoDisabled = false
        chatGPTAutoSource = nil
        claudeAutoSource = nil
        openCodeGoAutoSource = nil
        chatGPTNeedsFDA = false
        claudeNeedsFDA = false
        connectionNote = nil
        providerWarning = nil
        snapshot = .empty
        lastError = nil
        publishMenuBar()
        refreshNow()
    }

    /// Remove only ChatGPT credentials and its login-window cookies.
    func forgetChatGPT() {
        SessionSecrets.clear(.chatGPTSessionCookie)
        SessionSecrets.clear(.chatGPTBearerOverride)
        ProviderActivity.clear(.chatGPT)
        chatGPTConnected = false
        chatGPTConfigured = false
        chatGPTNeedsReconnect = false
        chatGPTAutoSource = nil
        chatGPTAuthFailedAt = nil
        chatGPTRecoveryDisabled = true
        snapshot.chatGPT = ProviderSnapshot(name: "ChatGPT", status: "", rows: [], fetchedAt: nil, error: nil)
        Task { await WebKitCookieBridge.clearChatGPTCookies() }
        updateProviderWarning()
        publishMenuBar()
        refreshNow()
    }

    /// Remove only Claude credentials and its login-window cookies.
    func forgetClaude() {
        SessionSecrets.clear(.claudeSessionCookie)
        SessionSecrets.clear(.claudeBearerOverride)
        ProviderActivity.clear(.claude)
        claudeConnected = false
        claudeConfigured = false
        claudeAutoSource = nil
        claudeNeedsFDA = false
        snapshot.claude = ProviderSnapshot(name: "Claude", status: "", rows: [], fetchedAt: nil, error: nil)
        Task { await WebKitCookieBridge.clearCookies(domainSuffix: "claude.ai") }
        updateProviderWarning()
        publishMenuBar()
        refreshNow()
    }

    /// Remove the Cursor token/cookie saved by the app.
    func forgetCursor() {
        SessionSecrets.clear(.cursorSessionCookie)
        SessionSecrets.clear(.cursorBearerOverride)
        ProviderActivity.clear(.cursor)
        cursorConnected = false
        cursorConfigured = false
        snapshot.cursor = ProviderSnapshot(name: "Cursor", status: "", rows: [], fetchedAt: nil, error: nil)
        updateProviderWarning()
        publishMenuBar()
        refreshNow()
    }

    func saveOpenCodeGoKey(_ key: String) {
        SessionSecrets.set(key, account: .openCodeGoAPIKey)
        openCodeGoAutoDisabled = false
        openCodeGoConfigured = true
        openCodeGoConnected = true
        openCodeGoAutoSource = L10n.tr("source.opencode_key")
        refreshNow()
    }

    /// Re-enable auto-detection from the local OpenCode login.
    func connectOpenCodeGo() {
        openCodeGoAutoDisabled = false
        refreshNow()
    }

    /// Remove OpenCode Go from the tray. The local OpenCode login is left alone;
    /// auto-detection stays disabled until the user explicitly reconnects.
    func forgetOpenCodeGo() {
        SessionSecrets.clear(.openCodeGoAPIKey)
        openCodeGoAutoDisabled = true
        ProviderActivity.clear(.openCodeGo)
        openCodeGoConnected = false
        openCodeGoConfigured = false
        openCodeGoAutoSource = nil
        snapshot.openCodeGo = ProviderSnapshot(name: "OpenCode Go", status: "", rows: [], fetchedAt: nil, error: nil)
        updateProviderWarning()
        publishMenuBar()
        refreshNow()
    }

    func openFullDiskAccessSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ]
        for s in urls {
            if let url = URL(string: s) {
                NSWorkspace.shared.open(url)
                return
            }
        }
    }

    /// Entry point for snapshots/probes/timer callers.
    func refresh() async {
        refreshGeneration &+= 1
        await refresh(generation: refreshGeneration)
    }

    private func isCurrent(_ generation: Int) -> Bool {
        generation == refreshGeneration && !Task.isCancelled
    }

    private func refresh(generation: Int) async {
        if AppPreferences.forceDemoMode || ProcessInfo.processInfo.arguments.contains("--demo") {
            applyDemoSnapshot()
            return
        }

        isRefreshing = true
        defer {
            if generation == refreshGeneration { isRefreshing = false }
        }

        // Recover a login-window session when the app Keychain was lost (e.g. after re-signing).
        await recoverChatGPTSecretsIfNeeded()
        guard isCurrent(generation) else { return }
        refreshConfiguredFlags()

        let openCodeGoAuth = resolveOpenCodeGoAuth()
        openCodeGoConfigured = openCodeGoAuth != nil
        let chatGPTIsConfigured = hasChatGPTSecrets
        let claudeIsConfigured = claudeConfigured
        let webRetryDue = chatGPTAuthFailedAt.map {
            Date().timeIntervalSince($0) >= 300
        } ?? true

        let cursorAuth = resolveCursorAuth()
        cursorConfigured = !(cursorAuth.bearerToken?.isEmpty ?? true)
            || !(cursorAuth.sessionCookie?.isEmpty ?? true)
        let chatGPTAuth = ChatGPTUsageClient.Auth(
            sessionCookie: SessionSecrets.get(.chatGPTSessionCookie),
            bearerToken: SessionSecrets.get(.chatGPTBearerOverride),
            accountID: nil
        )
        let claudeAuth = ClaudeUsageClient.Auth(
            sessionCookie: SessionSecrets.get(.claudeSessionCookie),
            bearerToken: SessionSecrets.get(.claudeBearerOverride)
        )

        // All providers run concurrently; one slow service must not delay the others.
        async let cursorFetch = ProviderFetcher.cursor(auth: cursorAuth)
        async let chatGPTFetch = fetchChatGPTIfConfigured(
            chatGPTIsConfigured,
            auth: chatGPTAuth,
            allowWeb: webRetryDue
        )
        async let claudeFetch = fetchClaudeIfConfigured(claudeIsConfigured, auth: claudeAuth)
        async let openCodeFetch = fetchOpenCodeGoIfConfigured(openCodeGoAuth)

        let (cursorOutcome, chatGPTOutcome, claudeOutcome, openCodeOutcome) =
            await (cursorFetch, chatGPTFetch, claudeFetch, openCodeFetch)
        guard isCurrent(generation) else { return }

        var next = snapshot
        next.isDemo = false

        cursorConnected = apply(cursorOutcome, previous: next.cursor, into: &next.cursor)
        if cursorConnected { markSuccess(.cursor, next.cursor) }

        if let chatGPTOutcome {
            chatGPTConfigured = true
            if chatGPTOutcome.webAttempted {
                if chatGPTOutcome.webAuthFailed {
                    // Stop hammering a session the server already rejected.
                    chatGPTAuthFailedAt = Date()
                } else {
                    chatGPTAuthFailedAt = nil
                }
            }
            chatGPTAutoSource = chatGPTOutcome.provider.source
            chatGPTNeedsReconnect = chatGPTOutcome.provider.authFailure
            chatGPTConnected = apply(chatGPTOutcome.provider, previous: next.chatGPT, into: &next.chatGPT)
            if chatGPTConnected { markSuccess(.chatGPT, next.chatGPT) }
        } else {
            chatGPTConnected = false
            chatGPTConfigured = false
            chatGPTAutoSource = nil
            chatGPTNeedsReconnect = false
            next.chatGPT = ProviderSnapshot(name: "ChatGPT", status: "", rows: [], fetchedAt: nil, error: nil)
        }

        if let claudeOutcome {
            claudeConnected = apply(claudeOutcome, previous: next.claude, into: &next.claude)
            if claudeConnected { markSuccess(.claude, next.claude) }
        } else {
            claudeConnected = false
            next.claude = ProviderSnapshot(name: "Claude", status: "", rows: [], fetchedAt: nil, error: nil)
        }

        if let openCodeOutcome {
            openCodeGoConfigured = true
            openCodeGoAutoSource = openCodeGoAuth?.source
            openCodeGoConnected = apply(openCodeOutcome, previous: next.openCodeGo, into: &next.openCodeGo)
            if openCodeGoConnected {
                markSuccess(.openCodeGo, next.openCodeGo)
                if let source = openCodeGoAutoSource, !source.isEmpty {
                    next.openCodeGo.status += " · \(source)"
                }
            }
        } else {
            openCodeGoConnected = false
            openCodeGoConfigured = false
            openCodeGoAutoSource = nil
            next.openCodeGo = ProviderSnapshot(name: "OpenCode Go", status: "", rows: [], fetchedAt: nil, error: nil)
        }

        snapshot = next
        lastError = [next.cursor.error, next.chatGPT.error, next.claude.error]
            .compactMap { $0 }
            .first
        updateProviderWarning()
        publishMenuBar()
        checkLowBalances()
    }

    private func checkLowBalances() {
        guard !snapshot.isDemo, AppPreferences.lowBalanceNotificationsEnabled else { return }

        let providers: [(String, ProviderSnapshot)] = [
            ("Cursor", snapshot.cursor),
            ("ChatGPT", snapshot.chatGPT),
            ("Claude", snapshot.claude),
            ("OpenCode Go", snapshot.openCodeGo)
        ]
        let now = Date()

        for (provider, providerSnapshot) in providers {
            for row in providerSnapshot.rows {
                guard let used = row.percentUsed else { continue }
                let remaining = Int((100 - used).rounded())
                let key = "lowBalanceNotified.\(provider).\(row.id)"

                if remaining > LowBalanceNotifier.threshold {
                    UserDefaults.standard.removeObject(forKey: key)
                    continue
                }

                let last = UserDefaults.standard.object(forKey: key) as? Date
                guard LowBalanceNotifier.shouldNotify(lastNotified: last, now: now) else { continue }
                UserDefaults.standard.set(now, forKey: key)
                NotificationService.shared.notifyLowBalance(
                    provider: provider,
                    limit: row.title,
                    remaining: remaining
                )
            }
        }
    }

    private func updateProviderWarning() {
        let failed: [String] = [
            (cursorConfigured && cursorVisible && !cursorConnected) ? "Cursor" : nil,
            (chatGPTConfigured && chatGPTVisible && !chatGPTConnected) ? "ChatGPT" : nil,
            (claudeConfigured && claudeVisible && !claudeConnected) ? "Claude" : nil,
            (openCodeGoConfigured && openCodeGoVisible && !openCodeGoConnected) ? "OpenCode Go" : nil
        ].compactMap { $0 }
        providerWarning = failed.first
    }

    private func hasPercentRows(_ snapshot: ProviderSnapshot) -> Bool {
        snapshot.rows.contains { $0.percentUsed != nil }
    }

    private func markSuccess(_ id: ProviderActivity.ID, _ snapshot: ProviderSnapshot) {
        guard hasPercentRows(snapshot) else { return }
        ProviderActivity.markSuccess(id)
    }

    private func fetchChatGPTIfConfigured(
        _ configured: Bool,
        auth: ChatGPTUsageClient.Auth,
        allowWeb: Bool
    ) async -> ChatGPTOutcome? {
        guard configured else { return nil }
        return await ProviderFetcher.chatGPT(auth: auth, allowWeb: allowWeb)
    }

    private struct OpenCodeGoAuth {
        let auth: OpenCodeGoUsageClient.Auth
        let source: String?
    }

    private func resolveOpenCodeGoAuth() -> OpenCodeGoAuth? {
        if let key = SessionSecrets.get(.openCodeGoAPIKey), !key.isEmpty {
            return OpenCodeGoAuth(auth: .init(apiKey: key), source: L10n.tr("source.opencode_key"))
        }
        guard !openCodeGoAutoDisabled, let local = OpenCodeLocalAuth.load() else { return nil }
        return OpenCodeGoAuth(auth: .init(apiKey: local.accessToken), source: L10n.tr("source.opencode_cli"))
    }

    private func fetchOpenCodeGoIfConfigured(_ auth: OpenCodeGoAuth?) async -> ProviderOutcome? {
        guard let auth else { return nil }
        return await ProviderFetcher.openCodeGo(auth: auth.auth)
    }

    private func fetchClaudeIfConfigured(
        _ configured: Bool,
        auth: ClaudeUsageClient.Auth
    ) async -> ProviderOutcome? {
        guard configured else { return nil }
        return await ProviderFetcher.claude(auth: auth)
    }

    /// Applies a fetch outcome to a provider snapshot, keeping stale rows on failure.
    /// Returns the new `connected` flag.
    @discardableResult
    private func apply(
        _ outcome: ProviderOutcome,
        previous: ProviderSnapshot,
        into target: inout ProviderSnapshot
    ) -> Bool {
        if let snapshot = outcome.snapshot {
            target = snapshot
            let connected = snapshot.error == nil && !snapshot.rows.isEmpty
            if connected {
                var status = connectedStatus(base: snapshot.status)
                if let source = outcome.source, !source.isEmpty {
                    status += " · \\(source)"
                }
                target.status = status
            }
            return connected
        }

        target = previous
        target.status = L10n.noConnection
        target.error = outcome.message ?? L10n.noConnection
        // A transient network blip keeps the last numbers in the tray; an auth
        // failure must not pretend the data is live.
        return !outcome.authFailure && !target.rows.isEmpty
    }

    /// Recover the app's ChatGPT cookie from its persistent WKWebView store when
    /// the Keychain item is missing (ad-hoc re-sign wipes its ACL).
    private func recoverChatGPTSecretsIfNeeded() async {
        guard !chatGPTRecoveryDisabled else { return }
        guard !hasChatGPTSecrets else { return }
        // The WKWebView cookie store and the migration path must not run while
        // the login Keychain is locked: that would show a password dialog.
        guard KeychainLock.isUnlocked else { return }
        guard let header = await WebKitCookieBridge.chatGPTSessionCookie() else { return }
        SessionSecrets.set(header, account: .chatGPTSessionCookie)
        chatGPTAutoSource = L10n.tr("source.webkit")
        chatGPTAuthFailedAt = nil
        refreshConfiguredFlags()
    }

    private func publishMenuBar() {
        let output = MenuBarPresenter.make(
            snapshot: snapshot,
            cursorConnected: cursorConnected,
            chatGPTConnected: chatGPTConnected,
            claudeConnected: claudeConnected,
            openCodeGoConnected: openCodeGoConnected
        )
        cursorSeverity = output.cursorSeverity
        chatGPTSeverity = output.chatGPTSeverity
        claudeSeverity = output.claudeSeverity
        openCodeGoSeverity = output.openCodeGoSeverity
        menuBarSegments = output.segments
        menuBarText = MenuBarPresenter.plainText(segments: output.segments)
        visibleProviderCount = [cursorVisible, chatGPTVisible, claudeVisible, openCodeGoVisible].filter { $0 }.count
    }

    private func resolveCursorAuth() -> CursorUsageClient.Auth {
        // Poll: never re-enter Cursor Safe Storage — cached app secrets only.
        if let override = SessionSecrets.get(.cursorBearerOverride), !override.isEmpty {
            return CursorUsageClient.Auth(bearerToken: override, sessionCookie: nil, userId: nil)
        }
        if let cookie = SessionSecrets.get(.cursorSessionCookie), !cookie.isEmpty {
            return CursorUsageClient.Auth(bearerToken: nil, sessionCookie: cookie, userId: nil)
        }
        if let local = SessionSecrets.cursorAuth() {
            return CursorUsageClient.Auth(bearerToken: local.accessToken, sessionCookie: nil, userId: local.userId)
        }
        return CursorUsageClient.Auth(bearerToken: nil, sessionCookie: nil, userId: nil)
    }

    private func connectedStatus(base: String) -> String {
        L10n.connectedWithDetail(base)
    }
}

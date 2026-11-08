import Foundation
import Combine
import AppKit

@MainActor
final class UsagePoller: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot = .empty
    @Published private(set) var isRefreshing = false
    @Published var lastError: String?

    @Published private(set) var cursorConnected = false
    @Published private(set) var chatGPTConnected = false
    @Published private(set) var claudeConnected = false
    /// True after user connected Claude (secrets in app Keychain). Hidden from tray/popover until then.
    @Published private(set) var claudeConfigured = false
    /// Compact menu-bar: icon+% for connected providers only. Empty if none.
    @Published private(set) var menuBarSegments: [MenuBarSegment] = []
    /// Accessibility / legacy plain text (e.g. `63% · 93%`).
    @Published private(set) var menuBarText: String = ""
    @Published private(set) var cursorSeverity: LimitSeverity = .unknown
    @Published private(set) var chatGPTSeverity: LimitSeverity = .unknown
    @Published private(set) var claudeSeverity: LimitSeverity = .unknown
    @Published var chatGPTNeedsFDA = false
    @Published var claudeNeedsFDA = false
    @Published var chatGPTAutoSource: String?
    @Published var claudeAutoSource: String?
    @Published var connectionNote: String?

    func applyDemoSnapshot() {
        snapshot = .demo
        lastError = nil
        cursorConnected = true
        chatGPTConnected = true
        claudeConnected = true
        claudeConfigured = true
        publishMenuBar()
    }

    private var timer: Timer?
    private var inFlight: Task<Void, Never>?
    private var didStart = false
    private var startObserver: NSObjectProtocol?

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
        if !hasChatGPTSecrets {
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
        inFlight?.cancel()
        inFlight = Task { await refresh() }
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

    /// «Взять сессию из браузера» — silent all, then at most ONE Keychain unlock.
    @discardableResult
    func connectChatGPTFromBrowserInteractive() async -> Bool {
        switch BrowserCookieReader.findChatGPTSessionCookie(allowKeychainPrompt: true) {
        case .found(let header, let source):
            SessionSecrets.set(header, account: .chatGPTSessionCookie)
            chatGPTAutoSource = source
            chatGPTNeedsFDA = false
            chatGPTConnected = true
            refreshNow()
            return true
        case .needsFullDiskAccess:
            chatGPTNeedsFDA = true
            return false
        case .notFound, .error:
            return false
        }
    }

    @discardableResult
    func connectClaudeFromBrowserInteractive() async -> Bool {
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

    /// Advanced only — may prompt Keychain.
    @discardableResult
    func connectCursorFromLocalInteractive() async -> Bool {
        if let creds = SessionSecrets.importCursorFromSafeStorageInteractive() {
            cursorConnected = true
            connectionNote = "Cursor: локальный токен"
            _ = creds
            refreshNow()
            return true
        }
        return false
    }

    func saveChatGPTCookie(_ header: String) {
        SessionSecrets.set(header, account: .chatGPTSessionCookie)
        chatGPTConnected = true
        chatGPTNeedsFDA = false
        connectionNote = "ChatGPT подключён"
        refreshNow()
    }

    func saveClaudeCookie(_ header: String) {
        SessionSecrets.set(header, account: .claudeSessionCookie)
        claudeConfigured = true
        claudeConnected = true
        claudeNeedsFDA = false
        connectionNote = "Claude подключён"
        refreshNow()
    }

    func clearStoredSecrets() {
        SessionSecrets.clearAll()
        chatGPTConnected = false
        claudeConnected = false
        claudeConfigured = false
        chatGPTAutoSource = nil
        claudeAutoSource = nil
        chatGPTNeedsFDA = false
        claudeNeedsFDA = false
        connectionNote = nil
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

    func refresh() async {
        if AppPreferences.forceDemoMode || ProcessInfo.processInfo.arguments.contains("--demo") {
            applyDemoSnapshot()
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        var next = snapshot
        next.isDemo = false

        // Cursor — memory / app Keychain only on poll (Safe Storage already done in start()).
        do {
            next.cursor = try await CursorUsageClient.fetch(auth: resolveCursorAuth())
            cursorConnected = next.cursor.error == nil && (!next.cursor.rows.isEmpty || next.cursor.status.contains("Подключено"))
            if cursorConnected && !next.cursor.status.contains("Подключено") {
                next.cursor.status = connectedStatus(base: next.cursor.status)
            }
        } catch {
            cursorConnected = false
            next.cursor = ProviderSnapshot(name: "Cursor", status: "Нет связи", rows: next.cursor.rows, fetchedAt: next.cursor.fetchedAt, error: humanize(error))
        }

        // ChatGPT — only if authorized (app Keychain secrets). Never show unauthorized.
        refreshConfiguredFlags()
        if hasChatGPTSecrets {
            do {
                next.chatGPT = try await ChatGPTUsageClient.fetch(auth: .init(
                    sessionCookie: SessionSecrets.get(.chatGPTSessionCookie),
                    bearerToken: SessionSecrets.get(.chatGPTBearerOverride)
                ))
                chatGPTConnected = next.chatGPT.error == nil && !next.chatGPT.rows.isEmpty
                if chatGPTConnected {
                    let src = chatGPTAutoSource.map { " · \($0)" } ?? ""
                    next.chatGPT.status = next.chatGPT.status.contains("Подключено") ? next.chatGPT.status : "Подключено\(src)"
                }
            } catch {
                chatGPTConnected = false
                next.chatGPT = ProviderSnapshot(name: "ChatGPT", status: "", rows: [], fetchedAt: next.chatGPT.fetchedAt, error: nil)
            }
        } else {
            chatGPTConnected = false
            next.chatGPT = ProviderSnapshot(name: "ChatGPT", status: "", rows: [], fetchedAt: nil, error: nil)
        }

        if claudeConfigured {
            do {
                next.claude = try await ClaudeUsageClient.fetch(auth: .init(
                    sessionCookie: SessionSecrets.get(.claudeSessionCookie),
                    bearerToken: SessionSecrets.get(.claudeBearerOverride)
                ))
                claudeConnected = next.claude.error == nil && (next.claude.status.contains("Подключено") || !next.claude.rows.isEmpty)
                if claudeConnected && next.claude.status.isEmpty {
                    next.claude.status = "Подключено"
                }
            } catch {
                claudeConnected = false
                next.claude = ProviderSnapshot(name: "Claude", status: "", rows: [], fetchedAt: next.claude.fetchedAt, error: nil)
            }
        } else {
            claudeConnected = false
            next.claude = ProviderSnapshot(name: "Claude", status: "", rows: [], fetchedAt: nil, error: nil)
        }

        snapshot = next
        lastError = [
            cursorConnected ? next.cursor.error : nil,
            chatGPTConnected ? next.chatGPT.error : nil,
            claudeConnected ? next.claude.error : nil
        ].compactMap { $0 }.first
        publishMenuBar()
    }

    private func publishMenuBar() {
        // Only connected providers with a live % — no letter placeholders.
        var segments: [MenuBarSegment] = []

        if cursorConnected, let cLeft = remainingPercent(from: snapshot.cursor) {
            cursorSeverity = severity(remaining: cLeft, connected: true)
            segments.append(MenuBarSegment(
                provider: .cursor,
                remainingPercent: Int(cLeft.rounded()),
                severity: cursorSeverity
            ))
        } else {
            cursorSeverity = .unknown
        }

        if chatGPTConnected, let gLeft = remainingPercent(from: snapshot.chatGPT) {
            chatGPTSeverity = severity(remaining: gLeft, connected: true)
            segments.append(MenuBarSegment(
                provider: .chatGPT,
                remainingPercent: Int(gLeft.rounded()),
                severity: chatGPTSeverity
            ))
        } else {
            chatGPTSeverity = .unknown
        }

        if claudeConnected, let aLeft = remainingPercent(from: snapshot.claude) {
            claudeSeverity = severity(remaining: aLeft, connected: true)
            segments.append(MenuBarSegment(
                provider: .claude,
                remainingPercent: Int(aLeft.rounded()),
                severity: claudeSeverity
            ))
        } else {
            claudeSeverity = .unknown
        }

        menuBarSegments = segments
        menuBarText = segments.map { "\($0.remainingPercent)%" }.joined(separator: " · ")
    }

    private func remainingPercent(from provider: ProviderSnapshot) -> Double? {
        guard let row = provider.rows.first(where: { $0.percentUsed != nil }), let used = row.percentUsed else { return nil }
        return max(0, min(100, 100 - used))
    }

    private func severity(remaining: Double?, connected: Bool) -> LimitSeverity {
        guard connected, let remaining else { return .unknown }
        switch remaining {
        case ..<15: return .critical
        case ..<35: return .low
        default: return .ok
        }
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
        if base.contains("Подключено") { return base }
        if base.isEmpty { return "Подключено" }
        return "Подключено · \(base)"
    }

    private func humanize(_ error: Error) -> String {
        (error as? UsageError)?.errorDescription ?? error.localizedDescription
    }

    private func humanizeChatGPT(_ error: Error) -> String {
        if let u = error as? UsageError, case .notConfigured = u {
            return "Нажмите «Подключить ChatGPT»."
        }
        return humanize(error)
    }

    private func humanizeClaude(_ error: Error) -> String {
        if let u = error as? UsageError, case .notConfigured = u {
            return "Нажмите «Подключить Claude» — или откройте приложение Claude на этом Mac."
        }
        return humanize(error)
    }
}

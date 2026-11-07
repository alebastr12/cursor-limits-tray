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
    /// Compact menu-bar string, e.g. `C75% · G40% · A60%`.
    @Published private(set) var menuBarText: String = "C— · G— · A—"
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
            // One-shot silent bootstrap — never again on the 45s timer.
            _ = SessionSecrets.cursorAuth()
            await autoConnectChatGPTIfNeeded()
            await autoConnectClaudeIfNeeded()
            await refresh()
        }
        restartTimer()
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

    @discardableResult
    func autoConnectChatGPTIfNeeded() async -> Bool {
        if let existing = SessionSecrets.get(.chatGPTSessionCookie), !existing.isEmpty {
            chatGPTConnected = true
            return true
        }
        if SessionSecrets.get(.chatGPTBearerOverride) != nil {
            chatGPTConnected = true
            return true
        }
        // Silent browser scan at most once per process — never on every poll.
        guard !SessionSecrets.didAttemptChatGPTBrowser else { return false }
        SessionSecrets.didAttemptChatGPTBrowser = true

        switch BrowserCookieReader.findChatGPTSessionCookie(allowKeychainPrompt: false) {
        case .found(let header, let source):
            SessionSecrets.set(header, account: .chatGPTSessionCookie)
            chatGPTAutoSource = source
            chatGPTNeedsFDA = false
            chatGPTConnected = true
            return true
        case .needsFullDiskAccess:
            chatGPTNeedsFDA = true
            return false
        case .notFound, .error:
            chatGPTNeedsFDA = false
            return false
        }
    }

    @discardableResult
    func autoConnectClaudeIfNeeded() async -> Bool {
        if let existing = SessionSecrets.get(.claudeSessionCookie), !existing.isEmpty {
            claudeConnected = true
            return true
        }
        if SessionSecrets.get(.claudeBearerOverride) != nil {
            claudeConnected = true
            return true
        }
        guard !SessionSecrets.didAttemptClaudeLocal else { return false }
        SessionSecrets.didAttemptClaudeLocal = true

        if let local = ClaudeLocalAuth.loadIfAvailable(allowKeychainPrompt: false) {
            if let cookie = local.sessionCookie {
                SessionSecrets.set(cookie, account: .claudeSessionCookie)
            }
            if let oauth = local.oauthAccessToken {
                SessionSecrets.set(oauth, account: .claudeBearerOverride)
            }
            claudeAutoSource = local.source
            claudeNeedsFDA = false
            claudeConnected = true
            connectionNote = "Claude: \(local.source)"
            return true
        }
        return false
    }

    @discardableResult
    func connectChatGPTFromBrowserInteractive() async -> Bool {
        // Explicit user action — may prompt once per browser Safe Storage (budgeted).
        SessionSecrets.didAttemptChatGPTBrowser = false
        switch BrowserCookieReader.findChatGPTSessionCookie(allowKeychainPrompt: true) {
        case .found(let header, let source):
            SessionSecrets.set(header, account: .chatGPTSessionCookie)
            chatGPTAutoSource = source
            chatGPTNeedsFDA = false
            chatGPTConnected = true
            SessionSecrets.didAttemptChatGPTBrowser = true
            refreshNow()
            return true
        case .needsFullDiskAccess:
            chatGPTNeedsFDA = true
            SessionSecrets.didAttemptChatGPTBrowser = true
            return false
        case .notFound, .error:
            SessionSecrets.didAttemptChatGPTBrowser = true
            return false
        }
    }

    @discardableResult
    func connectClaudeFromBrowserInteractive() async -> Bool {
        SessionSecrets.didAttemptClaudeLocal = false
        if let local = ClaudeLocalAuth.loadIfAvailable(allowKeychainPrompt: true) {
            if let cookie = local.sessionCookie {
                SessionSecrets.set(cookie, account: .claudeSessionCookie)
            }
            if let oauth = local.oauthAccessToken {
                SessionSecrets.set(oauth, account: .claudeBearerOverride)
            }
            claudeAutoSource = local.source
            claudeConnected = true
            claudeNeedsFDA = false
            SessionSecrets.didAttemptClaudeLocal = true
            refreshNow()
            return true
        }
        switch BrowserCookieReader.findClaudeSessionCookie(allowKeychainPrompt: true) {
        case .found(let header, let source):
            SessionSecrets.set(header, account: .claudeSessionCookie)
            claudeAutoSource = source
            claudeConnected = true
            SessionSecrets.didAttemptClaudeLocal = true
            refreshNow()
            return true
        case .needsFullDiskAccess:
            claudeNeedsFDA = true
            SessionSecrets.didAttemptClaudeLocal = true
            return false
        default:
            SessionSecrets.didAttemptClaudeLocal = true
            return false
        }
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
        claudeConnected = true
        claudeNeedsFDA = false
        connectionNote = "Claude подключён"
        refreshNow()
    }

    func clearStoredSecrets() {
        SessionSecrets.clearAll()
        chatGPTConnected = false
        claudeConnected = false
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

        // ChatGPT / Claude — use cached cookies only. Do NOT re-scan browsers here.
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
            next.chatGPT = ProviderSnapshot(name: "ChatGPT", status: "Не подключено", rows: [], fetchedAt: next.chatGPT.fetchedAt, error: humanizeChatGPT(error))
        }

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
            next.claude = ProviderSnapshot(name: "Claude", status: "Не подключено", rows: [], fetchedAt: next.claude.fetchedAt, error: humanizeClaude(error))
        }

        snapshot = next
        lastError = [next.cursor.error, next.chatGPT.error, next.claude.error].compactMap { $0 }.first
        publishMenuBar()
    }

    private func publishMenuBar() {
        let cLeft = remainingPercent(from: snapshot.cursor)
        let gLeft = remainingPercent(from: snapshot.chatGPT)
        let aLeft = remainingPercent(from: snapshot.claude)
        cursorSeverity = severity(remaining: cLeft, connected: cursorConnected)
        chatGPTSeverity = severity(remaining: gLeft, connected: chatGPTConnected)
        claudeSeverity = severity(remaining: aLeft, connected: claudeConnected)
        let c = cLeft.map { String(format: "%.0f%%", $0) } ?? "—"
        let g = gLeft.map { String(format: "%.0f%%", $0) } ?? "—"
        let a = aLeft.map { String(format: "%.0f%%", $0) } ?? "—"
        menuBarText = "C\(c) · G\(g) · A\(a)"
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
        if let override = SessionSecrets.get(.cursorBearerOverride), !override.isEmpty {
            return CursorUsageClient.Auth(bearerToken: override, sessionCookie: nil, userId: nil)
        }
        if let cookie = SessionSecrets.get(.cursorSessionCookie), !cookie.isEmpty {
            return CursorUsageClient.Auth(bearerToken: nil, sessionCookie: cookie, userId: nil)
        }
        // One silent attempt (cached inside SessionSecrets).
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

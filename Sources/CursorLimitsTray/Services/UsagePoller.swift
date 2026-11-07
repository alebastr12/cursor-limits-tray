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
    /// Compact menu-bar string, e.g. `C75% · G40%` or `C75% · G—`.
    @Published private(set) var menuBarText: String = "C— · G—"
    @Published private(set) var cursorSeverity: LimitSeverity = .unknown
    @Published private(set) var chatGPTSeverity: LimitSeverity = .unknown
    @Published var chatGPTNeedsFDA = false
    @Published var chatGPTAutoSource: String?
    @Published var connectionNote: String?

    func applyDemoSnapshot() {
        snapshot = .demo
        lastError = nil
        cursorConnected = true
        chatGPTConnected = true
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
        // When verifying the login panel, don't race Keychain/network against it.
        if ProcessInfo.processInfo.arguments.contains("--connect-chatgpt") {
            restartTimer()
            return
        }
        Task { await autoConnectChatGPTIfNeeded() }
        refreshNow()
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

    /// Tries browser cookies silently; returns true if a session was stored.
    @discardableResult
    func autoConnectChatGPTIfNeeded() async -> Bool {
        if let existing = KeychainStore.load(.chatGPTSessionCookie), !existing.isEmpty {
            chatGPTConnected = true
            return true
        }
        if KeychainStore.load(.chatGPTBearerOverride) != nil {
            chatGPTConnected = true
            return true
        }

        // Silent on launch — never pop Keychain UI (that stole focus from the login panel).
        switch BrowserCookieReader.findChatGPTSessionCookie(allowKeychainPrompt: false) {
        case .found(let header, let source):
            try? KeychainStore.save(header, account: .chatGPTSessionCookie)
            chatGPTAutoSource = source
            chatGPTNeedsFDA = false
            connectionNote = "ChatGPT: сессия из \(source)"
            chatGPTConnected = true
            return true
        case .needsFullDiskAccess:
            chatGPTNeedsFDA = true
            connectionNote = "Нужен доступ к диску, чтобы взять сессию из браузера — или нажмите «Подключить ChatGPT»."
            return false
        case .notFound, .error:
            chatGPTNeedsFDA = false
            return false
        }
    }

    /// Explicit user action — may show Keychain / FDA prompts.
    @discardableResult
    func connectChatGPTFromBrowserInteractive() async -> Bool {
        switch BrowserCookieReader.findChatGPTSessionCookie(allowKeychainPrompt: true) {
        case .found(let header, let source):
            try? KeychainStore.save(header, account: .chatGPTSessionCookie)
            chatGPTAutoSource = source
            chatGPTNeedsFDA = false
            chatGPTConnected = true
            connectionNote = "ChatGPT: сессия из \(source)"
            refreshNow()
            return true
        case .needsFullDiskAccess:
            chatGPTNeedsFDA = true
            return false
        case .notFound, .error:
            return false
        }
    }

    func saveChatGPTCookie(_ header: String) {
        try? KeychainStore.save(header, account: .chatGPTSessionCookie)
        chatGPTConnected = true
        chatGPTNeedsFDA = false
        connectionNote = "ChatGPT подключён"
        refreshNow()
    }

    func clearStoredSecrets() {
        KeychainStore.delete(.cursorSessionCookie)
        KeychainStore.delete(.cursorBearerOverride)
        KeychainStore.delete(.chatGPTSessionCookie)
        KeychainStore.delete(.chatGPTBearerOverride)
        chatGPTConnected = false
        chatGPTAutoSource = nil
        chatGPTNeedsFDA = false
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

        let cursorAuth = resolveCursorAuth()
        do {
            next.cursor = try await CursorUsageClient.fetch(auth: cursorAuth)
            cursorConnected = next.cursor.error == nil && !next.cursor.rows.isEmpty
            if cursorConnected {
                next.cursor.status = connectedStatus(base: next.cursor.status)
            }
        } catch {
            cursorConnected = false
            next.cursor = ProviderSnapshot(
                name: "Cursor",
                status: "Нет связи",
                rows: next.cursor.rows,
                fetchedAt: next.cursor.fetchedAt,
                error: humanize(error)
            )
        }

        // Retry browser auto-pickup if still disconnected.
        if !chatGPTConnected {
            _ = await autoConnectChatGPTIfNeeded()
        }

        let chatAuth = ChatGPTUsageClient.Auth(
            sessionCookie: KeychainStore.load(.chatGPTSessionCookie),
            bearerToken: KeychainStore.load(.chatGPTBearerOverride)
        )
        do {
            next.chatGPT = try await ChatGPTUsageClient.fetch(auth: chatAuth)
            chatGPTConnected = next.chatGPT.error == nil && !next.chatGPT.rows.isEmpty
            if chatGPTConnected {
                let src = chatGPTAutoSource.map { " · \($0)" } ?? ""
                next.chatGPT.status = "Подключено\(src)"
            }
        } catch {
            chatGPTConnected = false
            next.chatGPT = ProviderSnapshot(
                name: "ChatGPT",
                status: "Не подключено",
                rows: [],
                fetchedAt: next.chatGPT.fetchedAt,
                error: humanizeChatGPT(error)
            )
        }

        snapshot = next
        lastError = [next.cursor.error, next.chatGPT.error].compactMap { $0 }.first
        publishMenuBar()
    }

    private func publishMenuBar() {
        let cLeft = remainingPercent(from: snapshot.cursor)
        let gLeft = remainingPercent(from: snapshot.chatGPT)
        cursorSeverity = severity(remaining: cLeft, connected: cursorConnected)
        chatGPTSeverity = severity(remaining: gLeft, connected: chatGPTConnected)
        let c = cLeft.map { String(format: "%.0f%%", $0) } ?? "—"
        let g = gLeft.map { String(format: "%.0f%%", $0) } ?? "—"
        menuBarText = "C\(c) · G\(g)"
    }

    private func remainingPercent(from provider: ProviderSnapshot) -> Double? {
        guard let row = provider.rows.first, let used = row.percentUsed else { return nil }
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
        if let override = KeychainStore.load(.cursorBearerOverride), !override.isEmpty {
            return CursorUsageClient.Auth(bearerToken: override, sessionCookie: nil, userId: nil)
        }
        if let cookie = KeychainStore.load(.cursorSessionCookie), !cookie.isEmpty {
            return CursorUsageClient.Auth(bearerToken: nil, sessionCookie: cookie, userId: nil)
        }
        if let local = CursorLocalAuth.loadIfAvailable() {
            return CursorUsageClient.Auth(
                bearerToken: local.accessToken,
                sessionCookie: nil,
                userId: local.userId
            )
        }
        return CursorUsageClient.Auth(bearerToken: nil, sessionCookie: nil, userId: nil)
    }

    private func connectedStatus(base: String) -> String {
        if base.contains("Подключено") { return base }
        if base.isEmpty || base == "Not configured" { return "Подключено" }
        return "Подключено · \(base)"
    }

    private func humanize(_ error: Error) -> String {
        if let u = error as? UsageError {
            switch u {
            case .notConfigured: return "Войдите в приложение Cursor на этом Mac."
            default: return u.errorDescription ?? "Ошибка Cursor"
            }
        }
        return error.localizedDescription
    }

    private func humanizeChatGPT(_ error: Error) -> String {
        if let u = error as? UsageError {
            switch u {
            case .notConfigured:
                return "Нажмите «Подключить ChatGPT» — вход в одном окне, без DevTools."
            default:
                return u.errorDescription ?? "Ошибка ChatGPT"
            }
        }
        return error.localizedDescription
    }
}

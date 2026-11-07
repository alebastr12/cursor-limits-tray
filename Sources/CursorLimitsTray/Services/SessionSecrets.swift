import Foundation

/// Process-lifetime cache for tokens/cookies. Polling never re-hits Keychain or Safe Storage
/// when a value is already here.
@MainActor
enum SessionSecrets {
    private static var values: [KeychainStore.Account: String] = [:]
    private static var cursorCredentials: CursorLocalAuth.Credentials?
    private static var cursorLoadAttempted = false
    private static var chatGPTBrowserAttempted = false
    private static var claudeLocalAttempted = false

    static func get(_ account: KeychainStore.Account) -> String? {
        if let cached = values[account], !cached.isEmpty { return cached }
        if let loaded = KeychainStore.load(account, allowPrompt: false), !loaded.isEmpty {
            values[account] = loaded
            return loaded
        }
        return nil
    }

    static func set(_ value: String, account: KeychainStore.Account) {
        values[account] = value
        try? KeychainStore.save(value, account: account)
    }

    static func clear(_ account: KeychainStore.Account) {
        values.removeValue(forKey: account)
        KeychainStore.delete(account)
    }

    static func clearAll() {
        values.removeAll()
        cursorCredentials = nil
        cursorLoadAttempted = false
        chatGPTBrowserAttempted = false
        claudeLocalAttempted = false
        for account in KeychainStore.Account.allCases {
            KeychainStore.delete(account)
        }
        ChromiumCrypto.clearSessionCaches()
        BrowserCookieReader.resetPromptBudgetForReconnect()
    }

    /// Cursor token: read Safe Storage at most once per process (silent).
    static func cursorAuth() -> CursorLocalAuth.Credentials? {
        if let cursorCredentials { return cursorCredentials }
        if cursorLoadAttempted { return nil }
        cursorLoadAttempted = true
        if let creds = CursorLocalAuth.loadIfAvailable(allowKeychainPrompt: false) {
            cursorCredentials = creds
            // Persist so later launches skip Cursor Safe Storage until cleared.
            set(creds.accessToken, account: .cursorBearerOverride)
            return creds
        }
        return nil
    }

    static func invalidateCursorCache() {
        cursorCredentials = nil
        cursorLoadAttempted = false
    }

    /// Background/auto browser import — at most once per process unless reconnect.
    static var didAttemptChatGPTBrowser: Bool {
        get { chatGPTBrowserAttempted }
        set { chatGPTBrowserAttempted = newValue }
    }

    static var didAttemptClaudeLocal: Bool {
        get { claudeLocalAttempted }
        set { claudeLocalAttempted = newValue }
    }
}

extension KeychainStore.Account: CaseIterable {
    static var allCases: [KeychainStore.Account] {
        [.cursorSessionCookie, .cursorBearerOverride, .chatGPTSessionCookie, .chatGPTBearerOverride, .claudeSessionCookie, .claudeBearerOverride]
    }
}

import Foundation

/// Process-lifetime cache for tokens/cookies. Polling never re-hits foreign Safe Storage.
@MainActor
enum SessionSecrets {
    private static var values: [KeychainStore.Account: String] = [:]
    private static var cursorCredentials: CursorLocalAuth.Credentials?
    /// After one Safe Storage attempt (silent or the single interactive), never touch it again
    /// until Reset — even across launches (persisted when we got a token OR exhausted unlock).
    private static let cursorImportDoneKey = "cursor.safeStorageImportDone"

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
        UserDefaults.standard.removeObject(forKey: cursorImportDoneKey)
        for account in KeychainStore.Account.allCases {
            KeychainStore.delete(account)
        }
        ChromiumCrypto.clearPromptBudget()
        BrowserCookieReader.resetPromptBudgetForReconnect()
    }

    /// Cursor token from app Keychain, or one Safe Storage import (silent first; interactive only if
    /// global unlock budget still free and cache missing). Never re-reads Safe Storage after success/Reset gate.
    static func ensureCursorCached(allowInteractiveUnlock: Bool = false) -> CursorLocalAuth.Credentials? {
        if let cursorCredentials { return cursorCredentials }
        if let token = get(.cursorBearerOverride), !token.isEmpty {
            let creds = CursorLocalAuth.Credentials(accessToken: token, userId: nil, email: nil, membershipType: nil)
            cursorCredentials = creds
            return creds
        }

        // Already tried Safe Storage this install cycle — do not touch again.
        if UserDefaults.standard.bool(forKey: cursorImportDoneKey) {
            return nil
        }

        // 1) Silent only
        if let creds = CursorLocalAuth.loadIfAvailable(allowKeychainPrompt: false) {
            persistCursor(creds)
            return creds
        }

        // 2) Optional single interactive unlock (launch may pass true once; never with browser imports).
        if allowInteractiveUnlock, !ChromiumCrypto.hasUsedGlobalInteractiveUnlock {
            if let creds = CursorLocalAuth.loadIfAvailable(allowKeychainPrompt: true) {
                persistCursor(creds)
                return creds
            }
        }

        // Mark done so we don't keep hitting Safe Storage every launch (silent no-ops still cost ACL checks on some macOS builds).
        UserDefaults.standard.set(true, forKey: cursorImportDoneKey)
        return nil
    }

    private static func persistCursor(_ creds: CursorLocalAuth.Credentials) {
        cursorCredentials = creds
        set(creds.accessToken, account: .cursorBearerOverride)
        UserDefaults.standard.set(true, forKey: cursorImportDoneKey)
    }

    /// Launch/poll path — never prompts.
    static func cursorAuth() -> CursorLocalAuth.Credentials? {
        ensureCursorCached(allowInteractiveUnlock: false)
    }
}

extension KeychainStore.Account: CaseIterable {
    static var allCases: [KeychainStore.Account] {
        [.cursorSessionCookie, .cursorBearerOverride, .chatGPTSessionCookie, .chatGPTBearerOverride, .claudeSessionCookie, .claudeBearerOverride]
    }
}

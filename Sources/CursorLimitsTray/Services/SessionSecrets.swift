import Foundation

/// Process-lifetime cache. **Default path never touches foreign Safe Storage** (zero SecurityAgent).
@MainActor
enum SessionSecrets {
    private static var values: [KeychainStore.Account: String] = [:]
    private static var cursorCredentials: CursorLocalAuth.Credentials?

    static func get(_ account: KeychainStore.Account) -> String? {
        if let cached = values[account], !cached.isEmpty { return cached }
        // App-owned Keychain only — AfterFirstUnlockThisDeviceOnly, no ACL prompts in normal use.
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
        for account in KeychainStore.Account.allCases {
            KeychainStore.delete(account)
        }
        ChromiumCrypto.clearPromptBudget()
        BrowserCookieReader.resetPromptBudgetForReconnect()
    }

    /// Default / launch / poll: **app Keychain memory only**. Never opens Cursor Safe Storage.
    static func cursorAuth() -> CursorLocalAuth.Credentials? {
        if let cursorCredentials { return cursorCredentials }
        if let token = get(.cursorBearerOverride), !token.isEmpty {
            let creds = CursorLocalAuth.Credentials(accessToken: token, userId: nil, email: nil, membershipType: nil)
            cursorCredentials = creds
            return creds
        }
        return nil
    }

    /// Advanced only — may show a Keychain dialog (labeled in UI).
    static func importCursorFromSafeStorageInteractive() -> CursorLocalAuth.Credentials? {
        if let existing = cursorAuth() { return existing }
        guard !ChromiumCrypto.hasUsedGlobalInteractiveUnlock else { return nil }
        if let creds = CursorLocalAuth.loadIfAvailable(allowKeychainPrompt: true) {
            cursorCredentials = creds
            set(creds.accessToken, account: .cursorBearerOverride)
            return creds
        }
        return nil
    }

    /// Advanced: silent-only Safe Storage (still may ACL-prompt on some macOS builds — avoid on default path).
    static func importCursorFromSafeStorageSilent() -> CursorLocalAuth.Credentials? {
        if let existing = cursorAuth() { return existing }
        if let creds = CursorLocalAuth.loadIfAvailable(allowKeychainPrompt: false) {
            cursorCredentials = creds
            set(creds.accessToken, account: .cursorBearerOverride)
            return creds
        }
        return nil
    }
}

extension KeychainStore.Account: CaseIterable {
    static var allCases: [KeychainStore.Account] {
        [.cursorSessionCookie, .cursorBearerOverride, .chatGPTSessionCookie, .chatGPTBearerOverride, .claudeSessionCookie, .claudeBearerOverride]
    }
}

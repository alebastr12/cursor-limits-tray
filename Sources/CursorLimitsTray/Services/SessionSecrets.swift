import Foundation

/// Process-lifetime cache. **Default path never touches the Keychain or foreign Safe Storage.**
@MainActor
enum SessionSecrets {
    private static var values: [KeychainStore.Account: String] = [:]
    private static var cursorCredentials: CursorLocalAuth.Credentials?
    /// One-time migration from the old Keychain storage, per process.
    private static var migrationAttempted: Set<KeychainStore.Account> = []

    static func get(_ account: KeychainStore.Account) -> String? {
        if let cached = values[account], !cached.isEmpty { return cached }

        if let stored = FileSecretStore.all()[account.rawValue], !stored.isEmpty {
            values[account] = stored
            return stored
        }

        migrateFromKeychainIfPossible(account)
        return values[account]
    }

    static func set(_ value: String, account: KeychainStore.Account) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        values[account] = trimmed
        migrationAttempted.insert(account)
        SecretsPresence.mark(account)
        FileSecretStore.set(trimmed, account: account.rawValue)
    }

    static func clear(_ account: KeychainStore.Account) {
        values.removeValue(forKey: account)
        migrationAttempted.remove(account)
        SecretsPresence.clear(account)
        FileSecretStore.remove(account.rawValue)
        if account == .cursorSessionCookie || account == .cursorBearerOverride {
            cursorCredentials = nil
        }
    }

    static func clearAll() {
        values.removeAll()
        cursorCredentials = nil
        migrationAttempted.removeAll()
        SecretsPresence.clearAll()
        FileSecretStore.removeAll()
        ChromiumCrypto.clearPromptBudget()
        BrowserCookieReader.resetPromptBudgetForReconnect()
        ProviderActivity.clearAll()
    }

    /// Move an old Keychain item into the file store once, and only when the
    /// login Keychain is already unlocked. A locked Keychain would show a
    /// password dialog, which is exactly what the file store is meant to avoid.
    private static func migrateFromKeychainIfPossible(_ account: KeychainStore.Account) {
        // Only ChatGPT is auto-migrated: its v2 item has the any-app ACL. Cursor
        // and Claude may carry an older ACL that needs the login-keychain password;
        // Cursor has an explicit Settings button instead, Claude is reconnected.
        guard account == .chatGPTSessionCookie || account == .chatGPTBearerOverride else { return }
        guard KeychainLock.isUnlocked,
              SecretsPresence.has(account),
              !migrationAttempted.contains(account)
        else { return }
        migrationAttempted.insert(account)

        switch KeychainStore.loadResult(account, allowPrompt: false) {
        case .found(let value) where !value.isEmpty:
            values[account] = value
            FileSecretStore.set(value, account: account.rawValue)
            fputs("SessionSecrets: migrated \(account.rawValue) to file storage\n", stderr)
        case .missing:
            SecretsPresence.clear(account)
        default:
            break
        }
    }

    /// A legacy Keychain Cursor token exists but is not yet in the file store.
    static var hasLegacyCursorToken: Bool {
        guard SecretsPresence.has(.cursorBearerOverride) else { return false }
        let key = KeychainStore.Account.cursorBearerOverride.rawValue
        return FileSecretStore.all()[key] == nil
    }

    /// User-initiated migration: this is the only path allowed to show the
    /// login-keychain password prompt. After it succeeds, the token lives in
    /// the file store and future launches never touch the Keychain.
    static func importLegacyCursorTokenInteractively() -> Bool {
        switch KeychainStore.loadResult(.cursorBearerOverride, allowPrompt: true) {
        case .found(let value) where !value.isEmpty:
            set(value, account: .cursorBearerOverride)
            return true
        default:
            return false
        }
    }

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
        return ForeignKeychainGate.withForeignAccessAllowed {
            if let creds = CursorLocalAuth.loadIfAvailable(allowKeychainPrompt: true) {
                cursorCredentials = creds
                set(creds.accessToken, account: .cursorBearerOverride)
                return creds
            }
            return nil
        }
    }

    /// Advanced: silent-only Safe Storage (still may ACL-prompt — never call from launch/poll).
    static func importCursorFromSafeStorageSilent() -> CursorLocalAuth.Credentials? {
        if let existing = cursorAuth() { return existing }
        return ForeignKeychainGate.withForeignAccessAllowed {
            if let creds = CursorLocalAuth.loadIfAvailable(allowKeychainPrompt: false) {
                cursorCredentials = creds
                set(creds.accessToken, account: .cursorBearerOverride)
                return creds
            }
            return nil
        }
    }
}

extension KeychainStore.Account: CaseIterable {
    static var allCases: [KeychainStore.Account] {
        [.cursorSessionCookie, .cursorBearerOverride, .chatGPTSessionCookie, .chatGPTBearerOverride, .claudeSessionCookie, .claudeBearerOverride, .openCodeGoAPIKey]
    }
}

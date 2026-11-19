import Foundation

/// Process-lifetime cache. **Default path never touches foreign Safe Storage** (zero SecurityAgent).
@MainActor
enum SessionSecrets {
    private static var values: [KeychainStore.Account: String] = [:]
    private static var cursorCredentials: CursorLocalAuth.Credentials?

    static func get(_ account: KeychainStore.Account) -> String? {
        if let cached = values[account], !cached.isEmpty { return cached }
        // Fresh install / never saved: skip SecItem entirely.
        guard SecretsPresence.has(account) else { return nil }

        // App-owned Keychain only — v2 items carry a non-prompting ACL.
        switch KeychainStore.loadResult(account, allowPrompt: false) {
        case .found(let value) where !value.isEmpty:
            values[account] = value
            return value
        case .found, .missing:
            SecretsPresence.clear(account)
            return nil
        case .interactionRequired, .failed:
            // The v2 ACL should not need interaction; if the keychain is locked,
            // keep the marker so a later launch can retry.
            return nil
        }
    }

    static func set(_ value: String, account: KeychainStore.Account) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        values[account] = trimmed
        SecretsPresence.mark(account)
        do {
            try KeychainStore.save(trimmed, account: account)
        } catch {
            // Memory + presence still hold for this process; next launch may need reconnect.
            fputs("SessionSecrets: Keychain save failed for \(account.rawValue): \(error.localizedDescription)\n", stderr)
        }
    }

    static func clear(_ account: KeychainStore.Account) {
        values.removeValue(forKey: account)
        SecretsPresence.clear(account)
        KeychainStore.delete(account)
        if account == .cursorSessionCookie || account == .cursorBearerOverride {
            cursorCredentials = nil
        }
    }

    static func clearAll() {
        values.removeAll()
        cursorCredentials = nil
        SecretsPresence.clearAll()
        for account in KeychainStore.Account.allCases {
            KeychainStore.delete(account)
        }
        ChromiumCrypto.clearPromptBudget()
        BrowserCookieReader.resetPromptBudgetForReconnect()
        ProviderActivity.clearAll()
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
        [.cursorSessionCookie, .cursorBearerOverride, .chatGPTSessionCookie, .chatGPTBearerOverride, .claudeSessionCookie, .claudeBearerOverride]
    }
}

import Foundation

/// Process-lifetime cache. **Default path never touches foreign Safe Storage** (zero SecurityAgent).
@MainActor
enum SessionSecrets {
    private static var values: [KeychainStore.Account: String] = [:]
    private static var cursorCredentials: CursorLocalAuth.Credentials?
    private static let signatureKey = "keychain.signatureID"
    private static var didPrepareForLaunch = false
    /// Accounts whose Keychain read hit an ACL prompt/failure in this process.
    /// Avoids showing the same SecurityAgent dialog on every poll.
    private static var blockedAccounts: Set<KeychainStore.Account> = []

    /// Must run before any Keychain read.
    ///
    /// Old app-owned items are bound to the signing identity that created them.
    /// After a *later* re-sign, reading them can block on a SecurityAgent dialog,
    /// so we clear the presence markers and let the user reconnect once.
    static func prepareForLaunch() {
        guard !didPrepareForLaunch else { return }
        didPrepareForLaunch = true

        guard let signature = CodeSignature.stableID() else { return }
        let stored = UserDefaults.standard.string(forKey: signatureKey)
        guard stored != signature else { return }

        UserDefaults.standard.set(signature, forKey: signatureKey)
        // First launch of this guard: keep existing markers. The one-time macOS
        // prompt after the earlier signing change can still be approved by the user.
        guard stored != nil else { return }

        values.removeAll()
        cursorCredentials = nil
        blockedAccounts.removeAll()
        SecretsPresence.clearAll()
        fputs("SessionSecrets: signing identity changed; saved sessions need reconnecting\n", stderr)
    }

    static func get(_ account: KeychainStore.Account) -> String? {
        prepareForLaunch()
        if let cached = values[account], !cached.isEmpty { return cached }
        guard !blockedAccounts.contains(account) else { return nil }
        // Fresh install / never saved: skip SecItem entirely (avoids ACL password spam after re-sign).
        guard SecretsPresence.has(account) else { return nil }

        // App-owned Keychain only — never prompt.
        switch KeychainStore.loadResult(account, allowPrompt: false) {
        case .found(let value) where !value.isEmpty:
            values[account] = value
            return value
        case .found:
            SecretsPresence.clear(account)
            return nil
        case .missing:
            // Item is really gone (fresh install / reset) → drop presence so we stop
            // touching SecItem on every poll.
            SecretsPresence.clear(account)
            return nil
        case .interactionRequired, .failed:
            // The item still exists (locked keychain / changed ACL). Keep the
            // presence marker but do not retry in this process — otherwise the
            // same SecurityAgent dialog appears on every poll.
            blockedAccounts.insert(account)
            return nil
        }
    }

    static func set(_ value: String, account: KeychainStore.Account) {
        prepareForLaunch()
        blockedAccounts.remove(account)
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
        blockedAccounts.remove(account)
        SecretsPresence.clear(account)
        KeychainStore.delete(account)
        if account == .cursorSessionCookie || account == .cursorBearerOverride {
            cursorCredentials = nil
        }
    }

    static func clearAll() {
        values.removeAll()
        cursorCredentials = nil
        blockedAccounts.removeAll()
        SecretsPresence.clearAll()
        for account in KeychainStore.Account.allCases {
            KeychainStore.delete(account)
        }
        ChromiumCrypto.clearPromptBudget()
        BrowserCookieReader.resetPromptBudgetForReconnect()
        ProviderActivity.clearAll()
    }

    /// Default / launch / poll: **app Keychain memory only**. Never opens Cursor Safe Storage.
    /// Accounts whose saved items exist but need a one-time ACL approval after
    /// an app signature change. A never-used Claude login is intentionally not
    /// offered: its stale cookie should be disconnected, not restored.
    static var accountsNeedingPermission: [KeychainStore.Account] {
        KeychainStore.Account.allCases.filter { account in
            if (account == .claudeSessionCookie || account == .claudeBearerOverride),
               !ProviderActivity.hasSuccess(.claude) {
                return false
            }
            guard SecretsPresence.has(account) else { return false }
            switch KeychainStore.loadResult(account, allowPrompt: false) {
            case .interactionRequired, .failed:
                return true
            default:
                return false
            }
        }
    }

    /// User-initiated: show the macOS Keychain prompt and re-bind the item to the
    /// current signature by saving it again.
    @discardableResult
    static func restoreAccess(to account: KeychainStore.Account) -> Bool {
        guard case .found(let value) = KeychainStore.loadResult(account, allowPrompt: true),
              !value.isEmpty
        else { return false }
        values[account] = value
        SecretsPresence.mark(account)
        blockedAccounts.remove(account)
        try? KeychainStore.save(value, account: account)
        return true
    }

    static func restoreAllNeedingPermission() -> (restored: Int, failed: Int) {
        var restored = 0
        var failed = 0
        for account in accountsNeedingPermission {
            if restoreAccess(to: account) {
                restored += 1
            } else {
                failed += 1
            }
        }
        return (restored, failed)
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

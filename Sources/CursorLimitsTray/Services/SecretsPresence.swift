import Foundation

/// UserDefaults flags so launch/poll never hits Keychain when nothing was saved.
/// Ad-hoc re-signs often ACL-prompt once per stored item — skipping empty reads kills that spam.
enum SecretsPresence {
    private static let prefix = "secrets.present."

    static func has(_ account: KeychainStore.Account) -> Bool {
        UserDefaults.standard.bool(forKey: prefix + account.rawValue)
    }

    static func mark(_ account: KeychainStore.Account) {
        UserDefaults.standard.set(true, forKey: prefix + account.rawValue)
    }

    static func clear(_ account: KeychainStore.Account) {
        UserDefaults.standard.removeObject(forKey: prefix + account.rawValue)
    }

    static func clearAll() {
        for account in KeychainStore.Account.allCases {
            clear(account)
        }
    }
}

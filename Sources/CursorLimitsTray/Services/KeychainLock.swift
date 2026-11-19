import Foundation
import Security

/// Whether the default (login) Keychain is currently unlocked.
///
/// Reading or writing legacy Keychain items while it is locked always shows a
/// password dialog, regardless of ACLs. The app checks this before attempting a
/// one-time migration from the old Keychain storage.
enum KeychainLock {
    static var isUnlocked: Bool {
        var keychain: SecKeychain?
        guard SecKeychainCopyDefault(&keychain) == errSecSuccess, let keychain else {
            return false
        }
        var status: SecKeychainStatus = 0
        guard SecKeychainGetStatus(keychain, &status) == errSecSuccess else {
            return false
        }
        return (status & SecKeychainStatus(kSecUnlockStateStatus)) != 0
    }
}

import Foundation
import Security
import LocalAuthentication

enum KeychainStore {
    /// v2: items carry an ACL that is not bound to one code signature.
    ///
    /// The legacy service used the default per-app ACL, so every re-sign made
    /// macOS ask for the login-keychain password on launch and on connect. The
    /// v2 ACL allows any app and sets a zero prompt selector: the item stays
    /// encrypted by the login keychain, but no SecurityAgent dialog appears.
    /// This is the same practical access level as a 0600 file, with at-rest
    /// encryption. Old-service items are intentionally left untouched.
    private static let service = "local.cursor-limits-tray.v2"

    private static func anyAppAccess() -> SecAccess? {
        let description = "TrayAILimits" as CFString
        var access: SecAccess?
        guard SecAccessCreate(description, nil, &access) == errSecSuccess,
              let access
        else { return nil }

        var acls: CFArray?
        guard SecAccessCopyACLList(access, &acls) == errSecSuccess,
              let acl = (acls as? [SecACL])?.first
        else { return access }

        // nil application list = any application; zero prompt selector = no prompt.
        SecACLSetContents(acl, nil, description, SecKeychainPromptSelector(rawValue: 0))
        return access
    }

    enum Account: String {
        case cursorSessionCookie = "cursor.sessionCookie"
        case cursorBearerOverride = "cursor.bearerOverride"
        case chatGPTSessionCookie = "chatgpt.sessionCookie"
        case chatGPTBearerOverride = "chatgpt.bearerOverride"
        case claudeSessionCookie = "claude.sessionCookie"
        case claudeBearerOverride = "claude.bearerOverride"
    }

    static func save(_ value: String, account: Account) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        // After first unlock — no ACL prompt on every SecItemCopyMatching.
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        if let access = anyAppAccess() {
            attrs[kSecAttrAccess as String] = access
        }
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }
    }

    /// - Parameter allowPrompt: app-owned items should never need UI; keep fail-closed by default.
    static func load(_ account: Account, allowPrompt: Bool = false) -> String? {
        if case .found(let value) = loadResult(account, allowPrompt: allowPrompt) {
            return value
        }
        return nil
    }

    enum LoadResult {
        case found(String)
        case missing
        /// The item exists but macOS would need to ask the user (locked keychain,
        /// changed signature). Callers must keep their "secret exists" marker.
        case interactionRequired
        case failed(OSStatus)
    }

    static func loadResult(_ account: Account, allowPrompt: Bool = false) -> LoadResult {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if !allowPrompt {
            applySilentAuth(&query)
        }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
                return .missing
            }
            return .found(value)
        case errSecItemNotFound:
            return .missing
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled:
            return .interactionRequired
        default:
            return .failed(status)
        }
    }

    static func delete(_ account: Account) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func applySilentAuth(_ query: inout [String: Any]) {
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        let ctx = LAContext()
        ctx.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = ctx
    }

    enum KeychainError: LocalizedError {
        case unhandled(OSStatus)
        var errorDescription: String? {
            switch self {
            case .unhandled(let status):
                return "Keychain error \(status)"
            }
        }
    }
}

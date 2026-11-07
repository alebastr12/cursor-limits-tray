import Foundation
import Security
import LocalAuthentication

enum KeychainStore {
    private static let service = "local.cursor-limits-tray"

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
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }
    }

    /// - Parameter allowPrompt: app-owned items should never need UI; keep fail-closed by default.
    static func load(_ account: Account, allowPrompt: Bool = false) -> String? {
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
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
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

import Foundation
import CommonCrypto
import Security
import LocalAuthentication

enum ChromiumCrypto {
    private static var passwordCache: [String: String] = [:]
    /// Services we already showed a Keychain dialog for this process (Allow or Deny).
    private static var promptedThisProcess: Set<String> = []
    /// Persisted: interactive prompt already used for this Safe Storage service (until reconnect).
    private static let promptedDefaultsPrefix = "safeStorage.prompted."

    static func cacheKey(service: String, account: String) -> String {
        "\(service)|\(account)"
    }

    static func clearSessionCaches() {
        passwordCache.removeAll()
        promptedThisProcess.removeAll()
    }

    static func clearPromptBudget() {
        promptedThisProcess.removeAll()
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(promptedDefaultsPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    private static func hasUsedPromptBudget(service: String) -> Bool {
        if promptedThisProcess.contains(service) { return true }
        return UserDefaults.standard.bool(forKey: promptedDefaultsPrefix + service)
    }

    private static func markPromptUsed(service: String) {
        promptedThisProcess.insert(service)
        UserDefaults.standard.set(true, forKey: promptedDefaultsPrefix + service)
    }

    /// Read Chromium / Electron Safe Storage password.
    /// - Silent (`allowPrompt: false`): never shows UI; uses memory cache; `kSecUseAuthenticationUIFail`.
    /// - Interactive: at most one prompt per Safe Storage service until reconnect clears budget.
    static func keychainPassword(service: String, account: String = "Chrome", allowPrompt: Bool = false) -> String? {
        let key = cacheKey(service: service, account: account)
        if let cached = passwordCache[key] { return cached }

        if allowPrompt {
            // Already prompted for this browser Safe Storage (Allow Always or Deny) — don't spam.
            if hasUsedPromptBudget(service: service) {
                return keychainPasswordSilent(service: service, account: account, cacheKey: key)
            }
            markPromptUsed(service: service)
            if let pwd = keychainPasswordInteractive(service: service, account: account) {
                passwordCache[key] = pwd
                return pwd
            }
            return nil
        }

        return keychainPasswordSilent(service: service, account: account, cacheKey: key)
    }

    private static func keychainPasswordSilent(service: String, account: String, cacheKey: String) -> String? {
        var query: [String: Any] = baseQuery(service: service, account: account)
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        let ctx = LAContext()
        ctx.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = ctx

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data,
              let pwd = String(data: data, encoding: .utf8), !pwd.isEmpty else {
            return nil
        }
        passwordCache[cacheKey] = pwd
        return pwd
    }

    private static func keychainPasswordInteractive(service: String, account: String) -> String? {
        let query = baseQuery(service: service, account: account)
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data,
              let pwd = String(data: data, encoding: .utf8), !pwd.isEmpty else {
            return nil
        }
        return pwd
    }

    private static func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
    }

    static func pbkdf2(password: String, salt: Data = Data("saltysalt".utf8), keyByteCount: Int = 16, rounds: UInt32 = 1003) -> Data? {
        let passwordData = Data(password.utf8)
        var derived = Data(count: keyByteCount)
        let result = derived.withUnsafeMutableBytes { derivedBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: Int8.self).baseAddress,
                        passwordData.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        rounds,
                        derivedBytes.bindMemory(to: UInt8.self).baseAddress,
                        keyByteCount
                    )
                }
            }
        }
        return result == kCCSuccess ? derived : nil
    }

    /// Chromium cookie / safeStorage v10 AES-128-CBC (IV = 16 spaces).
    static func decryptV10(_ raw: Data, password: String) -> Data? {
        guard raw.count > 3 else { return nil }
        let prefix = String(data: raw.prefix(3), encoding: .utf8)
        guard prefix == "v10" || prefix == "v11" else { return nil }
        let encrypted = raw.dropFirst(3)
        guard let key = pbkdf2(password: password) else { return nil }
        let iv = Data(repeating: 0x20, count: 16)
        var out = Data(count: encrypted.count)
        var num = 0
        let status = out.withUnsafeMutableBytes { outBytes in
            encrypted.withUnsafeBytes { encBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, key.count,
                            ivBytes.baseAddress,
                            encBytes.baseAddress, encrypted.count,
                            outBytes.baseAddress, encrypted.count,
                            &num
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        out.count = num
        return out
    }

    /// Decode Chromium cookie bytes; Claude Desktop often prefixes 32 binary bytes.
    static func cookieUTF8(from decrypted: Data) -> String? {
        if let s = String(data: decrypted, encoding: .utf8), !s.isEmpty { return s }
        if decrypted.count > 32, let s = String(data: decrypted.dropFirst(32), encoding: .utf8), !s.isEmpty {
            return s
        }
        if let range = decrypted.range(of: Data("sk-ant".utf8)) {
            return String(data: decrypted[range.lowerBound...], encoding: .utf8)
        }
        return nil
    }
}

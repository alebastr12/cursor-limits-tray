import Foundation
import CommonCrypto
import Security
import LocalAuthentication

enum ChromiumCrypto {
    /// - Parameter allowPrompt: if false, never show Keychain UI (silent fail).
    static func keychainPassword(service: String, account: String = "Chrome", allowPrompt: Bool = false) -> String? {
        // Chrome uses account "Chrome", Brave "Brave", etc. Cursor uses "Cursor Key".
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        // Avoid modal Keychain dialogs stealing focus from the login panel.
        if !allowPrompt {
            // Prefer LAContext.interactionNotAllowed when available.
            let ctx = LAContext()
            ctx.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = ctx
        }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
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


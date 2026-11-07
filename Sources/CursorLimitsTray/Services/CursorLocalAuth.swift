import Foundation
import CommonCrypto
import SQLite3

/// Reads Cursor's locally stored access token (encrypted in state.vscdb via Keychain "Cursor Safe Storage").
enum CursorLocalAuth {
    struct Credentials {
        let accessToken: String
        let userId: String?
        let email: String?
        let membershipType: String?
    }

    /// Prefer `allowKeychainPrompt: false` — poll path must stay silent.
    /// Interactive prompt is only for an explicit reconnect (and ChromiumCrypto budgets it to once).
    static func loadIfAvailable(allowKeychainPrompt: Bool = false) -> Credentials? {
        guard let password = ChromiumCrypto.keychainPassword(
            service: "Cursor Safe Storage",
            account: "Cursor Key",
            allowPrompt: allowKeychainPrompt
        ) else {
            return nil
        }
        let dbPath = NSHomeDirectory() + "/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
        guard FileManager.default.fileExists(atPath: dbPath) else { return nil }

        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            return nil
        }
        defer { sqlite3_close(db) }

        guard let encrypted = stringValue(db: db, key: "cursorAuth/accessToken") else { return nil }
        guard let token = decryptCursorSafeStorage(encrypted, password: password) else { return nil }

        let email = stringValue(db: db, key: "cursorAuth/cachedEmail")
        let membership = stringValue(db: db, key: "cursorAuth/stripeMembershipType")
        var userId: String?
        if let profileJSON = stringValue(db: db, key: "cursorAuth/cachedScopedProfile"),
           let data = profileJSON.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let authId = obj["authId"] as? String {
            userId = authId.split(separator: "|").last.map(String.init) ?? authId
        }

        return Credentials(accessToken: token, userId: userId, email: email, membershipType: membership)
    }

    private static func stringValue(db: OpaquePointer, key: String) -> String? {
        let sql = "SELECT value FROM ItemTable WHERE key = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        if let cStr = sqlite3_column_text(stmt, 0) {
            return String(cString: cStr)
        }
        if let blob = sqlite3_column_blob(stmt, 0) {
            let size = Int(sqlite3_column_bytes(stmt, 0))
            let data = Data(bytes: blob, count: size)
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    /// Format: `cursor-safe-storage:v1:<base64(v10||ciphertext)>` — Chromium-style AES-128-CBC.
    private static func decryptCursorSafeStorage(_ value: String, password: String) -> String? {
        let parts = value.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[0] == "cursor-safe-storage", parts[1] == "v1" else { return nil }
        var b64 = parts[2]
        let pad = (4 - (b64.count % 4)) % 4
        if pad > 0 { b64 += String(repeating: "=", count: pad) }
        guard let raw = Data(base64Encoded: b64), raw.count > 3 else { return nil }
        let prefix = String(data: raw.prefix(3), encoding: .utf8)
        guard prefix == "v10" else { return nil }
        let encrypted = raw.dropFirst(3)

        guard let key = ChromiumCrypto.pbkdf2(password: password) else { return nil }
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
        return String(data: out, encoding: .utf8)
    }
}

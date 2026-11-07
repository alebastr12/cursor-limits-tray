import Foundation
import Security
import LocalAuthentication
import SQLite3

/// Reads Claude Desktop `sessionKey` and optional Claude Code OAuth token.
enum ClaudeLocalAuth {
    struct Credentials {
        var sessionCookie: String?
        var oauthAccessToken: String?
        var source: String
    }

    static func loadIfAvailable(allowKeychainPrompt: Bool = false) -> Credentials? {
        if let desktop = loadClaudeDesktopSession(allowKeychainPrompt: allowKeychainPrompt) {
            let oauth = loadClaudeCodeOAuth(allowKeychainPrompt: allowKeychainPrompt)
            return Credentials(sessionCookie: desktop.cookie, oauthAccessToken: oauth, source: desktop.source)
        }
        if let oauth = loadClaudeCodeOAuth(allowKeychainPrompt: allowKeychainPrompt) {
            return Credentials(sessionCookie: nil, oauthAccessToken: oauth, source: "Claude Code")
        }
        // Browser cookies for claude.ai
        switch BrowserCookieReader.findClaudeSessionCookie(allowKeychainPrompt: allowKeychainPrompt) {
        case .found(let header, let source):
            return Credentials(sessionCookie: header, oauthAccessToken: nil, source: source)
        default:
            return nil
        }
    }

    private static func loadClaudeDesktopSession(allowKeychainPrompt: Bool) -> (cookie: String, source: String)? {
        let dbPath = NSHomeDirectory() + "/Library/Application Support/Claude/Cookies"
        guard FileManager.default.fileExists(atPath: dbPath) else { return nil }
        guard let password = keychainPassword(
            service: "Claude Safe Storage",
            account: "Claude Key",
            allowPrompt: allowKeychainPrompt
        ) else { return nil }

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("clt-claude-\(UUID().uuidString).db")
        do {
            try FileManager.default.copyItem(atPath: dbPath, toPath: tmp.path)
        } catch {
            let ns = error as NSError
            if ns.domain == NSPOSIXErrorDomain && ns.code == 1 { return nil }
            return nil
        }
        defer { try? FileManager.default.removeItem(at: tmp) }

        var db: OpaquePointer?
        guard sqlite3_open_v2(tmp.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else { return nil }
        defer { sqlite3_close(db) }

        let sql = "SELECT name, encrypted_value, value FROM cookies WHERE host_key LIKE '%claude.ai%' AND name IN ('sessionKey','sessionKeyV3');"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return nil }
        defer { sqlite3_finalize(stmt) }

        var sessionKey: String?
        while sqlite3_step(stmt) == SQLITE_ROW {
            let name = String(cString: sqlite3_column_text(stmt, 0))
            var value = ""
            if let plain = sqlite3_column_text(stmt, 2) {
                value = String(cString: plain)
            }
            if value.isEmpty, let blob = sqlite3_column_blob(stmt, 1) {
                let size = Int(sqlite3_column_bytes(stmt, 1))
                let data = Data(bytes: blob, count: size)
                value = decryptChromiumCookie(data, password: password) ?? ""
            }
            if value.hasPrefix("sk-ant") {
                if name == "sessionKey" || sessionKey == nil {
                    sessionKey = value
                }
            }
        }
        guard let sessionKey else { return nil }
        return (cookie: "sessionKey=\(sessionKey)", source: "Claude Desktop")
    }

    private static func loadClaudeCodeOAuth(allowKeychainPrompt: Bool) -> String? {
        guard let raw = keychainPassword(
            service: "Claude Code-credentials",
            account: NSUserName(),
            allowPrompt: allowKeychainPrompt
        ) ?? keychainPassword(service: "Claude Code-credentials", account: "alebastr", allowPrompt: allowKeychainPrompt) else {
            return nil
        }
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let oauth = obj["claudeAiOauth"] as? [String: Any],
           let token = oauth["accessToken"] as? String, !token.isEmpty {
            return token
        }
        return nil
    }

    private static func decryptChromiumCookie(_ raw: Data, password: String) -> String? {
        guard let plain = ChromiumCrypto.decryptV10(raw, password: password) else { return nil }
        // Claude Desktop often stores a 32-byte binary prefix before the UTF-8 cookie.
        if plain.count > 32, let s = String(data: plain.dropFirst(32), encoding: .utf8), s.hasPrefix("sk-ant") {
            return s
        }
        if let s = String(data: plain, encoding: .utf8), s.hasPrefix("sk-ant") {
            return s
        }
        // Search for sk-ant inside decrypted bytes
        if let range = plain.range(of: Data("sk-ant".utf8)) {
            return String(data: plain[range.lowerBound...], encoding: .utf8)
        }
        return nil
    }

    private static func keychainPassword(service: String, account: String, allowPrompt: Bool) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if !allowPrompt {
            let ctx = LAContext()
            ctx.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = ctx
        }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

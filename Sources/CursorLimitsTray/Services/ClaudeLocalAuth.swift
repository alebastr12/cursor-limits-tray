import Foundation
import SQLite3

/// Reads Claude Desktop `sessionKey` and optional Claude Code OAuth token.
enum ClaudeLocalAuth {
    struct Credentials {
        var sessionCookie: String?
        var oauthAccessToken: String?
        var source: String
    }

    /// Silent-only import (launch / poll). Never shows Keychain UI.
    static func loadSilent() -> Credentials? {
        if let desktop = loadClaudeDesktopSession(allowKeychainPrompt: false) {
            let oauth = loadClaudeCodeOAuth(allowKeychainPrompt: false)
            return Credentials(sessionCookie: desktop.cookie, oauthAccessToken: oauth, source: desktop.source)
        }
        if let oauth = loadClaudeCodeOAuth(allowKeychainPrompt: false) {
            return Credentials(sessionCookie: nil, oauthAccessToken: oauth, source: "Claude Code")
        }
        switch BrowserCookieReader.findClaudeSessionCookie(allowKeychainPrompt: false) {
        case .found(let header, let source):
            return Credentials(sessionCookie: header, oauthAccessToken: nil, source: source)
        default:
            return nil
        }
    }

    /// User clicked «Взять сессию»: silent everything first; then unlock **one** preferred store and stop.
    static func loadWithSingleUnlock() -> Credentials? {
        if let silent = loadSilent() { return silent }

        // Prefer Claude Desktop Safe Storage (one dialog), not a cascade of browsers.
        if !ChromiumCrypto.hasUsedGlobalInteractiveUnlock {
            if let desktop = loadClaudeDesktopSession(allowKeychainPrompt: true) {
                return Credentials(sessionCookie: desktop.cookie, oauthAccessToken: nil, source: desktop.source)
            }
        }

        // If Desktop missing/denied and budget still free, try ONE browser unlock path.
        if !ChromiumCrypto.hasUsedGlobalInteractiveUnlock {
            switch BrowserCookieReader.findClaudeSessionCookie(allowKeychainPrompt: true) {
            case .found(let header, let source):
                return Credentials(sessionCookie: header, oauthAccessToken: nil, source: source)
            default:
                break
            }
        }

        // Never also unlock Claude Code in the same action if we already spent the budget.
        if !ChromiumCrypto.hasUsedGlobalInteractiveUnlock,
           let oauth = loadClaudeCodeOAuth(allowKeychainPrompt: true) {
            return Credentials(sessionCookie: nil, oauthAccessToken: oauth, source: "Claude Code")
        }

        return nil
    }

    /// Legacy name — maps to silent (callers must not use for cascading prompts).
    static func loadIfAvailable(allowKeychainPrompt: Bool = false) -> Credentials? {
        allowKeychainPrompt ? loadWithSingleUnlock() : loadSilent()
    }

    private static func loadClaudeDesktopSession(allowKeychainPrompt: Bool) -> (cookie: String, source: String)? {
        let dbPath = NSHomeDirectory() + "/Library/Application Support/Claude/Cookies"
        guard FileManager.default.fileExists(atPath: dbPath) else { return nil }
        guard let password = ChromiumCrypto.keychainPassword(
            service: "Claude Safe Storage",
            account: "Claude Key",
            allowPrompt: allowKeychainPrompt
        ) else { return nil }

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("clt-claude-\(UUID().uuidString).db")
        do {
            try FileManager.default.copyItem(atPath: dbPath, toPath: tmp.path)
        } catch {
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
        let account = NSUserName()
        guard let raw = ChromiumCrypto.keychainPassword(
            service: "Claude Code-credentials",
            account: account,
            allowPrompt: allowKeychainPrompt
        ) else { return nil }
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
        if plain.count > 32, let s = String(data: plain.dropFirst(32), encoding: .utf8), s.hasPrefix("sk-ant") {
            return s
        }
        if let s = String(data: plain, encoding: .utf8), s.hasPrefix("sk-ant") {
            return s
        }
        if let range = plain.range(of: Data("sk-ant".utf8)) {
            return String(data: plain[range.lowerBound...], encoding: .utf8)
        }
        return nil
    }
}

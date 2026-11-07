import Foundation
import SQLite3

enum BrowserCookieReader {
    enum Outcome {
        case found(cookieHeader: String, source: String)
        case needsFullDiskAccess
        case notFound
        case error(String)
    }

    struct BrowserProfile {
        let name: String
        let cookiesPath: String
        let keychainService: String
        let keychainAccount: String
    }

    static let chromiumProfiles: [BrowserProfile] = [
        BrowserProfile(
            name: "Chrome",
            cookiesPath: NSHomeDirectory() + "/Library/Application Support/Google/Chrome/Default/Cookies",
            keychainService: "Chrome Safe Storage",
            keychainAccount: "Chrome"
        ),
        BrowserProfile(
            name: "Chrome Profile 1",
            cookiesPath: NSHomeDirectory() + "/Library/Application Support/Google/Chrome/Profile 1/Cookies",
            keychainService: "Chrome Safe Storage",
            keychainAccount: "Chrome"
        ),
        BrowserProfile(
            name: "Brave",
            cookiesPath: NSHomeDirectory() + "/Library/Application Support/BraveSoftware/Brave-Browser/Default/Cookies",
            keychainService: "Brave Safe Storage",
            keychainAccount: "Brave"
        ),
        BrowserProfile(
            name: "Arc",
            cookiesPath: NSHomeDirectory() + "/Library/Application Support/Arc/User Data/Default/Cookies",
            keychainService: "Arc Safe Storage",
            keychainAccount: "Arc"
        ),
        BrowserProfile(
            name: "Edge",
            cookiesPath: NSHomeDirectory() + "/Library/Application Support/Microsoft Edge/Default/Cookies",
            keychainService: "Microsoft Edge Safe Storage",
            keychainAccount: "Microsoft Edge"
        )
    ]

    static func resetPromptBudgetForReconnect() {
        ChromiumCrypto.clearPromptBudget()
    }

    /// ChatGPT cookies. Interactive: silent scan all → at most ONE Safe Storage unlock → stop.
    static func findChatGPTSessionCookie(allowKeychainPrompt: Bool = false) -> Outcome {
        findSession(
            allowKeychainPrompt: allowKeychainPrompt,
            read: readChromiumChatGPTCookies
        )
    }

    /// Claude.ai cookies in Chromium browsers (not Claude Desktop).
    static func findClaudeSessionCookie(allowKeychainPrompt: Bool = false) -> Outcome {
        findSession(
            allowKeychainPrompt: allowKeychainPrompt,
            read: readClaudeCookies
        )
    }

    private static func findSession(
        allowKeychainPrompt: Bool,
        read: (String, String, String, Bool) throws -> String?
    ) -> Outcome {
        let existing = chromiumProfiles.filter { FileManager.default.fileExists(atPath: $0.cookiesPath) }
        guard !existing.isEmpty else { return .notFound }

        var sawPermissionDenied = false

        // Pass 1: silent only — never shows SecurityAgent.
        for profile in existing {
            do {
                if let header = try read(profile.cookiesPath, profile.keychainService, profile.keychainAccount, false),
                   !header.isEmpty {
                    return .found(cookieHeader: header, source: profile.name)
                }
            } catch CookieReadError.permissionDenied {
                sawPermissionDenied = true
            } catch {
                continue
            }
        }

        guard allowKeychainPrompt else {
            if sawPermissionDenied { return .needsFullDiskAccess }
            return .notFound
        }

        // Pass 2: unlock exactly ONE Safe Storage (first profile whose silent key was missing), then stop.
        if ChromiumCrypto.hasUsedGlobalInteractiveUnlock {
            if sawPermissionDenied { return .needsFullDiskAccess }
            return .notFound
        }

        for profile in existing {
            // Skip if silent already had the password (would have succeeded in pass 1 if cookies existed).
            let cacheKey = ChromiumCrypto.cacheKey(service: profile.keychainService, account: profile.keychainAccount)
            _ = cacheKey
            do {
                if let header = try read(profile.cookiesPath, profile.keychainService, profile.keychainAccount, true),
                   !header.isEmpty {
                    return .found(cookieHeader: header, source: profile.name)
                }
                // Interactive was attempted inside ChromiumCrypto (budget consumed) — do not cascade.
                if ChromiumCrypto.hasUsedGlobalInteractiveUnlock {
                    break
                }
            } catch CookieReadError.permissionDenied {
                sawPermissionDenied = true
                if ChromiumCrypto.hasUsedGlobalInteractiveUnlock { break }
            } catch CookieReadError.noKey {
                // Budget may have been spent on a denied/cancel dialog.
                if ChromiumCrypto.hasUsedGlobalInteractiveUnlock { break }
                continue
            } catch {
                if ChromiumCrypto.hasUsedGlobalInteractiveUnlock { break }
                continue
            }
        }

        if sawPermissionDenied { return .needsFullDiskAccess }
        return .notFound
    }

    private enum CookieReadError: Error {
        case permissionDenied
        case openFailed
        case noKey
    }

    private static func readClaudeCookies(
        dbPath: String,
        keychainService: String,
        keychainAccount: String,
        allowKeychainPrompt: Bool
    ) throws -> String? {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("clt-claude-br-\(UUID().uuidString).db")
        do {
            try FileManager.default.copyItem(atPath: dbPath, toPath: tmp.path)
        } catch {
            let ns = error as NSError
            if ns.domain == NSPOSIXErrorDomain && ns.code == 1 { throw CookieReadError.permissionDenied }
            return try queryClaudeCookies(dbPath: dbPath, keychainService: keychainService, keychainAccount: keychainAccount, allowKeychainPrompt: allowKeychainPrompt)
        }
        defer { try? FileManager.default.removeItem(at: tmp) }
        return try queryClaudeCookies(dbPath: tmp.path, keychainService: keychainService, keychainAccount: keychainAccount, allowKeychainPrompt: allowKeychainPrompt)
    }

    private static func queryClaudeCookies(
        dbPath: String,
        keychainService: String,
        keychainAccount: String,
        allowKeychainPrompt: Bool
    ) throws -> String? {
        guard let password = ChromiumCrypto.keychainPassword(service: keychainService, account: keychainAccount, allowPrompt: allowKeychainPrompt) else {
            throw CookieReadError.noKey
        }
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            throw CookieReadError.openFailed
        }
        defer { sqlite3_close(db) }
        let sql = "SELECT name, encrypted_value, value FROM cookies WHERE host_key LIKE '%claude.ai%' AND name IN ('sessionKey','sessionKeyV3');"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return nil }
        defer { sqlite3_finalize(stmt) }
        var session: String?
        while sqlite3_step(stmt) == SQLITE_ROW {
            let name = String(cString: sqlite3_column_text(stmt, 0))
            var value = ""
            if let plain = sqlite3_column_text(stmt, 2) { value = String(cString: plain) }
            if value.isEmpty, let blob = sqlite3_column_blob(stmt, 1) {
                let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(stmt, 1)))
                if let dec = ChromiumCrypto.decryptV10(data, password: password) {
                    value = ChromiumCrypto.cookieUTF8(from: dec) ?? ""
                }
            }
            if value.hasPrefix("sk-ant"), name == "sessionKey" || session == nil {
                session = value
            }
        }
        guard let session else { return nil }
        return "sessionKey=\(session)"
    }

    private static func readChromiumChatGPTCookies(
        dbPath: String,
        keychainService: String,
        keychainAccount: String,
        allowKeychainPrompt: Bool
    ) throws -> String? {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("clt-cookies-\(UUID().uuidString).db")
        do {
            try FileManager.default.copyItem(atPath: dbPath, toPath: tmp.path)
            for suffix in ["-wal", "-shm"] {
                let side = dbPath + suffix
                if FileManager.default.fileExists(atPath: side) {
                    try? FileManager.default.copyItem(atPath: side, toPath: tmp.path + suffix)
                }
            }
        } catch {
            let ns = error as NSError
            if ns.domain == NSPOSIXErrorDomain && ns.code == 1 {
                throw CookieReadError.permissionDenied
            }
            return try queryCookies(
                dbPath: dbPath,
                keychainService: keychainService,
                keychainAccount: keychainAccount,
                allowKeychainPrompt: allowKeychainPrompt
            )
        }

        defer {
            try? FileManager.default.removeItem(at: tmp)
            try? FileManager.default.removeItem(atPath: tmp.path + "-wal")
            try? FileManager.default.removeItem(atPath: tmp.path + "-shm")
        }
        return try queryCookies(
            dbPath: tmp.path,
            keychainService: keychainService,
            keychainAccount: keychainAccount,
            allowKeychainPrompt: allowKeychainPrompt
        )
    }

    private static func queryCookies(
        dbPath: String,
        keychainService: String,
        keychainAccount: String,
        allowKeychainPrompt: Bool
    ) throws -> String? {
        guard let password = ChromiumCrypto.keychainPassword(
            service: keychainService,
            account: keychainAccount,
            allowPrompt: allowKeychainPrompt
        ) else {
            throw CookieReadError.noKey
        }

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(dbPath, &db, flags, nil) == SQLITE_OK, let db else {
            throw CookieReadError.openFailed
        }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT name, encrypted_value, value, host_key
        FROM cookies
        WHERE host_key LIKE '%chatgpt.com%'
          AND (name LIKE '%next-auth.session-token%' OR name = '__Secure-next-auth.session-token');
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        var parts: [(name: String, value: String)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let nameC = sqlite3_column_text(stmt, 0) else { continue }
            let name = String(cString: nameC)
            var value = ""
            if let plainC = sqlite3_column_text(stmt, 2) {
                value = String(cString: plainC)
            }
            if value.isEmpty {
                if let blob = sqlite3_column_blob(stmt, 1) {
                    let size = Int(sqlite3_column_bytes(stmt, 1))
                    let data = Data(bytes: blob, count: size)
                    if let dec = ChromiumCrypto.decryptV10(data, password: password) {
                        value = ChromiumCrypto.cookieUTF8(from: dec) ?? ""
                    }
                }
            }
            if !value.isEmpty {
                parts.append((name, value))
            }
        }

        guard !parts.isEmpty else { return nil }

        let byName = Dictionary(uniqueKeysWithValues: parts.map { ($0.name, $0.value) })
        if let z = byName["__Secure-next-auth.session-token.0"],
           let o = byName["__Secure-next-auth.session-token.1"] {
            return "__Secure-next-auth.session-token.0=\(z); __Secure-next-auth.session-token.1=\(o)"
        }
        if let single = byName["__Secure-next-auth.session-token"] {
            return "__Secure-next-auth.session-token=\(single)"
        }
        return parts.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }
}

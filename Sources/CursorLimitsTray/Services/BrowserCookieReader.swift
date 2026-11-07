import Foundation
import SQLite3

enum BrowserCookieReader {
    enum Outcome {
        case found(cookieHeader: String, source: String)
        case needsFullDiskAccess
        case notFound
        case error(String)
    }

    /// Looks for ChatGPT session cookies in Chromium-based browsers.
    /// - Parameter allowKeychainPrompt: only true for explicit user action («Взять сессию из браузера»).
    static func findChatGPTSessionCookie(allowKeychainPrompt: Bool = false) -> Outcome {
        let profiles: [(name: String, cookiesPath: String, keychainService: String, keychainAccount: String)] = [
            (
                "Chrome",
                NSHomeDirectory() + "/Library/Application Support/Google/Chrome/Default/Cookies",
                "Chrome Safe Storage",
                "Chrome"
            ),
            (
                "Chrome Profile 1",
                NSHomeDirectory() + "/Library/Application Support/Google/Chrome/Profile 1/Cookies",
                "Chrome Safe Storage",
                "Chrome"
            ),
            (
                "Brave",
                NSHomeDirectory() + "/Library/Application Support/BraveSoftware/Brave-Browser/Default/Cookies",
                "Brave Safe Storage",
                "Brave"
            ),
            (
                "Arc",
                NSHomeDirectory() + "/Library/Application Support/Arc/User Data/Default/Cookies",
                "Arc Safe Storage",
                "Arc"
            ),
            (
                "Edge",
                NSHomeDirectory() + "/Library/Application Support/Microsoft Edge/Default/Cookies",
                "Microsoft Edge Safe Storage",
                "Microsoft Edge"
            )
        ]

        var sawPermissionDenied = false
        var sawExistingDB = false

        for profile in profiles {
            let path = profile.cookiesPath
            guard FileManager.default.fileExists(atPath: path) else { continue }
            sawExistingDB = true

            do {
                let header = try readChromiumChatGPTCookies(
                    dbPath: path,
                    keychainService: profile.keychainService,
                    keychainAccount: profile.keychainAccount,
                    allowKeychainPrompt: allowKeychainPrompt
                )
                if let header, !header.isEmpty {
                    return .found(cookieHeader: header, source: profile.name)
                }
            } catch CookieReadError.permissionDenied {
                sawPermissionDenied = true
            } catch {
                continue
            }
        }

        if sawPermissionDenied { return .needsFullDiskAccess }
        if sawExistingDB { return .notFound }
        return .notFound
    }

    private enum CookieReadError: Error {
        case permissionDenied
        case openFailed
        case noKey
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
            // Also copy WAL/SHM if present for consistency
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
            // Fall through: try opening original path
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
                    if let dec = ChromiumCrypto.decryptV10(data, password: password),
                       let s = String(data: dec, encoding: .utf8) {
                        value = s
                    }
                }
            }
            if !value.isEmpty {
                parts.append((name, value))
            }
        }

        guard !parts.isEmpty else { return nil }

        // Prefer sharded pair if present, else single token.
        let byName = Dictionary(uniqueKeysWithValues: parts.map { ($0.name, $0.value) })
        if let z = byName["__Secure-next-auth.session-token.0"],
           let o = byName["__Secure-next-auth.session-token.1"] {
            return "__Secure-next-auth.session-token.0=\(z); __Secure-next-auth.session-token.1=\(o)"
        }
        if let single = byName["__Secure-next-auth.session-token"] {
            return "__Secure-next-auth.session-token=\(single)"
        }
        // Any leftover session-looking cookies
        return parts.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }
}

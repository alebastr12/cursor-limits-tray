import Foundation
import SQLite3

/// Reads the local OpenCode Console credential (the same token OpenCode uses).
/// The Go usage API accepts it as a Bearer token; no separate Go API key is
/// required for users signed in to OpenCode.
enum OpenCodeLocalAuth {
    struct Credentials {
        let accessToken: String
        let source: String
    }

    private enum ReadResult {
        case found(Credentials)
        case noCredential
        case failed
    }

    static func load() -> Credentials? {
        for path in databasePaths() where FileManager.default.fileExists(atPath: path) {
            switch read(path: path) {
            case .found(let credentials):
                return credentials
            case .noCredential:
                continue
            case .failed:
                if let credentials = readFromCopy(path: path) {
                    return credentials
                }
            }
        }
        return nil
    }

    /// Test seam: points `load()` at a fixture database.
    static var databasePathOverride: String?

    private static func databasePaths() -> [String] {
        if let databasePathOverride { return [databasePathOverride] }
        var paths: [String] = []
        if let xdg = ProcessInfo.processInfo.environment["XDG_DATA_HOME"], !xdg.isEmpty {
            paths.append(xdg + "/opencode/opencode.db")
        }
        paths.append(NSHomeDirectory() + "/.local/share/opencode/opencode.db")
        paths.append(NSHomeDirectory() + "/Library/Application Support/opencode/opencode.db")
        return paths
    }

    /// Read-only; the DB may be open in WAL mode. A 36 MB copy is only made
    /// when the direct read fails (busy/locked).
    private static func readFromCopy(path: String) -> Credentials? {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
            .appendingPathComponent("opencode-credential-\(UUID().uuidString).db")
        do {
            try fm.copyItem(atPath: path, toPath: tmp.path)
            for suffix in ["-wal", "-shm"] where fm.fileExists(atPath: path + suffix) {
                try? fm.copyItem(atPath: path + suffix, toPath: tmp.path + suffix)
            }
        } catch {
            return nil
        }
        defer {
            try? fm.removeItem(at: tmp)
            try? fm.removeItem(atPath: tmp.path + "-wal")
            try? fm.removeItem(atPath: tmp.path + "-shm")
        }
        if case .found(let credentials) = read(path: tmp.path) {
            return credentials
        }
        return nil
    }

    private static func read(path: String) -> ReadResult {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK, let db else {
            return .failed
        }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT value FROM credential
        WHERE integration_id = 'opencode' AND active = 1
        ORDER BY time_updated DESC LIMIT 1;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return .failed
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW,
              let text = sqlite3_column_text(stmt, 0)
        else { return .noCredential }

        let raw = String(cString: text)
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = object["access"] as? String,
              !access.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return .noCredential }

        return .found(Credentials(accessToken: access, source: "OpenCode CLI"))
    }
}

import Foundation

/// App-owned sessions, stored outside the Keychain.
///
/// The login Keychain asks for its password whenever it is locked (for example
/// on a login-item launch) and its ACLs are tied to the code signature. A 0600
/// file in Application Support has neither problem. Access is equivalent to the
/// previous any-app Keychain ACL: the user's own apps can read it, but the file
/// is not world-readable. FileVault protects it at rest.
enum FileSecretStore {
    private static var cache: [String: String]?

    static var directoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TrayAILimits", isDirectory: true)
    }

    static var fileURL: URL {
        directoryURL.appendingPathComponent("secrets.json")
    }

    static func all() -> [String: String] {
        if let cache { return cache }
        guard let data = try? Data(contentsOf: fileURL),
              let values = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            cache = [:]
            return [:]
        }
        cache = values
        return values
    }

    static func set(_ value: String, account: String) {
        var values = all()
        values[account] = value
        write(values)
    }

    static func remove(_ account: String) {
        var values = all()
        values.removeValue(forKey: account)
        write(values)
    }

    static func removeAll() {
        cache = [:]
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func write(_ values: [String: String]) {
        cache = values
        let fm = FileManager.default
        do {
            try fm.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)

            let data = try JSONEncoder().encode(values)
            try data.write(to: fileURL, options: .atomic)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            fputs("FileSecretStore: write failed: \(error.localizedDescription)\n", stderr)
        }
    }
}

import Foundation

/// Foreign Safe Storage (Cursor / Chrome / Claude / browsers) must NEVER be touched on the
/// default launch/poll path — even "silent" SecItemCopyMatching can ACL-prompt on macOS.
enum ForeignKeychainGate {
    private static var depth = 0

    /// True only inside Advanced / explicit import handlers.
    static var allowsForeignAccess: Bool { depth > 0 }

    static func withForeignAccessAllowed<T>(_ body: () throws -> T) rethrows -> T {
        depth += 1
        defer { depth -= 1 }
        return try body()
    }

    static func withForeignAccessAllowed<T>(_ body: () async throws -> T) async rethrows -> T {
        depth += 1
        defer { depth -= 1 }
        return try await body()
    }
}

import Foundation

/// Remembers whether a provider has ever produced usable data (a row with a %).
///
/// A stale login cookie can leave `configured == true` with no working session.
/// Such a provider must not occupy the popover or raise a tray warning until it
/// has actually worked at least once. Persisted so an expired session on a later
/// launch still shows a meaningful "session expired" error.
enum ProviderActivity {
    enum ID: String, CaseIterable {
        case cursor
        case chatGPT = "chatgpt"
        case claude
        case openCodeGo = "opencodego"
    }

    private static let prefix = "provider.lastSuccess."

    static func markSuccess(_ id: ID, at date: Date = Date()) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: prefix + id.rawValue)
    }

    static func hasSuccess(_ id: ID) -> Bool {
        UserDefaults.standard.object(forKey: prefix + id.rawValue) != nil
    }

    static func clear(_ id: ID) {
        UserDefaults.standard.removeObject(forKey: prefix + id.rawValue)
    }

    static func clearAll() {
        ID.allCases.forEach(clear)
    }

    /// A configured provider is only worth showing if it is connected, still has
    /// usable rows, or has produced real data at least once. This hides a stale
    /// login cookie for a service the user never actually used.
    static func isVisible(
        id: ID,
        connected: Bool,
        snapshot: ProviderSnapshot
    ) -> Bool {
        connected
            || snapshot.rows.contains { $0.percentUsed != nil }
            || hasSuccess(id)
    }
}

import Foundation

/// What we keep from chatgpt.com's cookie jar.
///
/// Only the NextAuth session (incl. chunked `.0`/`.1`), the active workspace
/// (`_account`) and a few routing/anti-abuse ids are useful for `backend-api`.
/// Analytics/consent/Cloudflare cookies are deliberately dropped: they inflate
/// the Keychain item, are short-lived, and `cf_clearance` is TLS-bound anyway.
enum ChatGPTCookieHeader {
    private static let extraNames: Set<String> = ["_account", "oai-did", "oai-sc", "_puid"]

    static func isRelevant(_ name: String) -> Bool {
        name.contains("next-auth.session-token") || extraNames.contains(name)
    }

    /// Stable header with a required session cookie; `nil` when there is no session.
    static func build(from pairs: [(name: String, value: String)]) -> String? {
        let relevant = pairs.filter { isRelevant($0.name) && !$0.value.isEmpty }
        guard relevant.contains(where: { $0.name.contains("next-auth.session-token") }) else {
            return nil
        }
        // Lexicographic order keeps chunked `.0` before `.1`.
        return relevant
            .sorted { $0.name < $1.name }
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
    }
}

import Foundation

/// Read-only access to the Codex CLI OAuth session (`~/.codex/auth.json`).
///
/// Used only as a fallback when the app's own chatgpt.com web session can no
/// longer mint access tokens. The token is never copied into the app Keychain:
/// the file is re-read on every poll, so Codex's own refresh keeps it current.
enum CodexLocalAuth {
    struct Credentials {
        let accessToken: String
        let accountID: String?
    }

    static func load() -> Credentials? {
        let url = authFileURL()
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = root["tokens"] as? [String: Any],
              let rawToken = tokens["access_token"] as? String
        else { return nil }

        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !JWTClaims.isExpired(token, leeway: 120) else { return nil }

        var accountID = (tokens["account_id"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if accountID?.isEmpty != false {
            accountID = JWTClaims.chatGPTAccountID(from: token)
        }
        return Credentials(accessToken: token, accountID: accountID)
    }

    /// Test seam: lets integration tests point the Codex fallback at a fixture.
    static var authFileOverride: URL?

    static func authFileURL() -> URL {
        if let authFileOverride { return authFileOverride }
        if let home = ProcessInfo.processInfo.environment["CODEX_HOME"],
           !home.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: home).appendingPathComponent("auth.json")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")
    }
}

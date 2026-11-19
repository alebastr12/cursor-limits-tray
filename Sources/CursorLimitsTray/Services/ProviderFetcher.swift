import Foundation

/// One provider fetch result. `snapshot == nil` means the fetch failed and the
/// caller should keep the previous rows (but still show `message`).
struct ProviderOutcome {
    var snapshot: ProviderSnapshot?
    var message: String?
    var authFailure: Bool = false
    var source: String?

    static func success(_ snapshot: ProviderSnapshot, source: String? = nil) -> ProviderOutcome {
        ProviderOutcome(snapshot: snapshot, message: nil, authFailure: false, source: source)
    }

    static func failure(_ error: Error) -> ProviderOutcome {
        let usage = error as? UsageError
        return ProviderOutcome(
            snapshot: nil,
            message: usage?.errorDescription ?? error.localizedDescription,
            authFailure: usage?.isAuthFailure ?? false,
            source: nil
        )
    }
}

struct ChatGPTOutcome {
    var provider: ProviderOutcome
    /// The web session was actually attempted in this refresh.
    var webAttempted: Bool
    /// The web session was rejected (not a transient network error).
    var webAuthFailed: Bool
}

/// Network + auth policy per provider, without any published UI state.
/// Lets `UsagePoller` run the three providers concurrently.
enum ProviderFetcher {
    static func cursor(auth: CursorUsageClient.Auth) async -> ProviderOutcome {
        do {
            return .success(try await CursorUsageClient.fetch(auth: auth))
        } catch {
            return .failure(error)
        }
    }

    static func claude(auth: ClaudeUsageClient.Auth) async -> ProviderOutcome {
        do {
            return .success(try await ClaudeUsageClient.fetch(auth: auth))
        } catch {
            return .failure(error)
        }
    }

    static func openCodeGo(auth: OpenCodeGoUsageClient.Auth) async -> ProviderOutcome {
        do {
            return .success(try await OpenCodeGoUsageClient.fetch(auth: auth))
        } catch {
            return .failure(error)
        }
    }

    /// Web session first; on any failure fall back to the local Codex login.
    /// The Codex token is re-read on every poll and never persisted by the app.
    static func chatGPT(auth: ChatGPTUsageClient.Auth, allowWeb: Bool) async -> ChatGPTOutcome {
        var webFailure: Error?

        if allowWeb {
            do {
                let snapshot = try await ChatGPTUsageClient.fetch(auth: auth)
                return ChatGPTOutcome(
                    provider: .success(snapshot),
                    webAttempted: true,
                    webAuthFailed: false
                )
            } catch {
                webFailure = error
            }
        }

        if let codex = CodexLocalAuth.load() {
            do {
                let snapshot = try await ChatGPTUsageClient.fetch(auth: .init(
                    sessionCookie: nil,
                    bearerToken: codex.accessToken,
                    accountID: codex.accountID
                ))
                return ChatGPTOutcome(
                    provider: .success(snapshot, source: L10n.tr("source.codex_cli")),
                    webAttempted: allowWeb,
                    webAuthFailed: (webFailure as? UsageError)?.isAuthFailure ?? false
                )
            } catch {
                if webFailure == nil { webFailure = error }
            }
        }

        let failure = webFailure ?? UsageError.notConfigured(L10n.tr("error.connect_chatgpt"))
        return ChatGPTOutcome(
            provider: .failure(failure),
            webAttempted: allowWeb,
            webAuthFailed: (failure as? UsageError)?.isAuthFailure ?? false
        )
    }
}

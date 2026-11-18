import Foundation
import WebKit

/// Reads cookies the app's own login window stored in the persistent WKWebView
/// data store. This survives app re-signing (unlike Keychain ACLs) and lets the
/// poller recover a session without asking for a password.
@MainActor
enum WebKitCookieBridge {
    /// ChatGPT cookie header, or `nil` when no NextAuth session exists.
    static func chatGPTSessionCookie() async -> String? {
        let store = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await store.allCookies()
        return chatGPTCookieHeader(from: cookies)
    }

    /// Builds a header from the live chatgpt.com cookies (see `ChatGPTCookieHeader`
    /// for the allow-list and why workspace routing needs more than the session).
    static func chatGPTCookieHeader(from cookies: [HTTPCookie]) -> String? {
        let now = Date()
        let pairs = cookies
            .filter { cookie in
                guard cookie.domain.hasSuffix("chatgpt.com") else { return false }
                if let expires = cookie.expiresDate, expires < now { return false }
                return true
            }
            .map { (name: $0.name, value: $0.value) }
        return ChatGPTCookieHeader.build(from: pairs)
    }

    /// Explicit "Reset Secrets" must also end the login-window session,
    /// otherwise the poller would immediately recover it.
    static func clearChatGPTCookies() async {
        let store = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await store.allCookies()
        for cookie in cookies where cookie.domain.hasSuffix("chatgpt.com") {
            await store.delete(cookie)
        }
    }
}

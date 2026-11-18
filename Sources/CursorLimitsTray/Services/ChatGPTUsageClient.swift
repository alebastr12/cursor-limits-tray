import Foundation

enum ChatGPTUsageClient {
    struct Auth {
        var sessionCookie: String?
        var bearerToken: String?
        var accountID: String?
    }

    private static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private static let sessionURL = URL(string: "https://chatgpt.com/api/auth/session")!
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15 CursorLimitsTray/0.2"

    private struct Session {
        let accessToken: String
        let accountID: String?
    }

    static func fetch(auth: Auth) async throws -> ProviderSnapshot {
        var bearer: String
        var cookieHeader: String?
        var accountID = auth.accountID?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let override = auth.bearerToken?.trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            bearer = stripBearerPrefix(override)
            if accountID?.isEmpty != false {
                accountID = JWTClaims.chatGPTAccountID(from: bearer)
            }
        } else if let cookie = normalizeCookie(auth.sessionCookie) {
            let session = try await exchangeSessionCookie(cookie)
            bearer = session.accessToken
            if accountID?.isEmpty != false { accountID = session.accountID }
            cookieHeader = cookie
        } else {
            throw UsageError.notConfigured(L10n.tr("error.connect_chatgpt"))
        }

        var headers = [
            "Authorization": "Bearer \(bearer)",
            "User-Agent": userAgent,
            "Accept": "application/json",
            "Cache-Control": "no-cache",
            "Pragma": "no-cache"
        ]
        // Same-origin cookie helps Cloudflare / workspace routing.
        if let cookieHeader { headers["Cookie"] = cookieHeader }
        if let accountID, !accountID.isEmpty {
            headers["ChatGPT-Account-Id"] = accountID
        }

        let json = try await getJSON(url: usageURL, headers: headers)
        return mapUsage(json)
    }

    // MARK: - Session cookie → access token

    private static func normalizeCookie(_ raw: String?) -> String? {
        guard var trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        if trimmed.lowercased().hasPrefix("cookie:") {
            trimmed = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        }
        if trimmed.contains("=") { return trimmed }
        // Bare token → single session cookie name.
        return "__Secure-next-auth.session-token=\(trimmed)"
    }

    private static func stripBearerPrefix(_ value: String) -> String {
        value.lowercased().hasPrefix("bearer ")
            ? String(value.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            : value
    }

    private static func exchangeSessionCookie(_ cookie: String) async throws -> Session {
        var request = URLRequest(url: sessionURL)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, http) = try await HTTPClient.data(for: request)
        guard http.statusCode == 200 else {
            throw UsageError.http(http.statusCode, String(data: data, encoding: .utf8))
        }
        let json = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]

        // NextAuth reports an invalidated refresh token here while still returning
        // the old (expired) accessToken — surface the real cause instead of a 401.
        if let sessionError = json["error"] as? String, !sessionError.isEmpty {
            throw UsageError.authExpired(L10n.tr("error.chatgpt_expired"))
        }

        guard let token = (json["accessToken"] as? String) ?? (json["access_token"] as? String),
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw UsageError.auth(L10n.tr("error.chatgpt_no_token"))
        }
        guard !JWTClaims.isExpired(token) else {
            throw UsageError.authExpired(L10n.tr("error.chatgpt_expired"))
        }

        let accountID = JWTClaims.chatGPTAccountID(from: token) ?? accountIDFromCookies(cookie)
        return Session(accessToken: token, accountID: accountID)
    }

    /// Workspace accounts carry the active workspace in the `_account` cookie.
    private static func accountIDFromCookies(_ header: String) -> String? {
        for pair in header.split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2, parts[0] == "_account" else { continue }
            if let id = JWTClaims.chatGPTAccountID(from: parts[1]), !id.isEmpty { return id }
        }
        return nil
    }

    // MARK: - Networking

    private static func getJSON(url: URL, headers: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let object = try await HTTPClient.json(for: request, authExpiredBodyMarker: "token_expired")
        return (object as? [String: Any]) ?? [:]
    }

    // MARK: - Mapping

    /// Internal for parser tests (`@testable import`).
    static func mapUsage(_ json: [String: Any]) -> ProviderSnapshot {
        // Responses vary: sometimes nested under "usage", sometimes top-level rate_limit.
        let root = (json["usage"] as? [String: Any]) ?? json
        let planType = (root["plan_type"] as? String) ?? (json["plan_type"] as? String) ?? "ChatGPT"
        let rate = (root["rate_limit"] as? [String: Any]) ?? [:]
        let limitReached = (rate["limit_reached"] as? Bool) ?? false

        var rows: [LimitRow] = []

        if let primary = rate["primary_window"] as? [String: Any] {
            rows.append(windowRow(
                id: "cgpt-primary",
                fallbackTitle: L10n.tr("limit.window_5h"),
                detail: L10n.tr("limit.primary"),
                window: primary
            ))
        }
        if let secondary = rate["secondary_window"] as? [String: Any] {
            rows.append(windowRow(
                id: "cgpt-secondary",
                fallbackTitle: L10n.tr("limit.week"),
                detail: L10n.tr("limit.secondary"),
                window: secondary
            ))
        }

        // Per-model caps: each entry has its own primary/secondary windows.
        if let extras = rate["additional_rate_limits"] as? [[String: Any]] ?? json["additional_rate_limits"] as? [[String: Any]] {
            for (idx, extra) in extras.enumerated() {
                let name = (extra["title"] as? String)
                    ?? (extra["feature_name"] as? String)
                    ?? (extra["name"] as? String)
                    ?? L10n.tr("limit.extra", idx + 1)
                let id = (extra["id"] as? String) ?? "\(idx)"

                var emitted = false
                for (suffix, key, fallbackTitle) in [
                    ("primary", "primary_window", L10n.tr("limit.window_5h")),
                    ("secondary", "secondary_window", L10n.tr("limit.week"))
                ] {
                    guard let window = extra[key] as? [String: Any] else { continue }
                    emitted = true
                    rows.append(windowRow(
                        id: "cgpt-extra-\(id)-\(suffix)",
                        fallbackTitle: fallbackTitle,
                        prefix: name,
                        detail: name,
                        window: window
                    ))
                }
                // Legacy shape: window fields directly on the extra object.
                if !emitted, doubleValue(extra["used_percent"]) != nil {
                    rows.append(windowRow(
                        id: "cgpt-extra-\(id)",
                        fallbackTitle: name,
                        detail: L10n.tr("limit.primary"),
                        window: extra
                    ))
                }
            }
        }

        if let credits = root["credits"] as? [String: Any] {
            let unlimited = credits["unlimited"] as? Bool ?? false
            let hasCredits = credits["has_credits"] as? Bool ?? false
            if hasCredits || unlimited {
                rows.append(
                    LimitRow(
                        id: "cgpt-credits",
                        title: L10n.tr("limit.credits"),
                        detail: L10n.tr("limit.credits_detail"),
                        percentUsed: nil,
                        remainingLabel: creditsBalanceLabel(credits["balance"], unlimited: unlimited),
                        resetLabel: nil
                    )
                )
            }
        }

        var statusBits = [planType.capitalized]
        if limitReached { statusBits.append(L10n.tr("status.limit_reached")) }

        return ProviderSnapshot(
            name: "ChatGPT",
            status: statusBits.joined(separator: " · "),
            rows: rows,
            fetchedAt: Date(),
            error: rows.isEmpty ? L10n.tr("error.chatgpt_no_windows") : nil
        )
    }

    private static func creditsBalanceLabel(_ balance: Any?, unlimited: Bool) -> String {
        if unlimited { return L10n.tr("limit.unlimited") }
        if let s = balance as? String { return s }
        if let n = balance as? NSNumber { return n.stringValue }
        return "—"
    }

    private static func windowRow(
        id: String,
        fallbackTitle: String,
        prefix: String? = nil,
        detail: String,
        window: [String: Any]
    ) -> LimitRow {
        let used = (doubleValue(window["used_percent"]) ?? doubleValue(window["usedPercent"]))
            .map { min(max($0, 0), 100) }
        let remaining: String?
        if let used {
            remaining = L10n.remainingPercent(100 - used)
        } else if let rem = doubleValue(window["remaining"]) {
            remaining = L10n.tr("limit.remaining_count", Int(rem))
        } else {
            remaining = nil
        }

        let reset: String?
        if let resetAt = window["reset_at"] as? TimeInterval ?? (window["reset_at"] as? NSNumber).map(\.doubleValue) {
            let date = Date(timeIntervalSince1970: resetAt > 10_000_000_000 ? resetAt / 1000 : resetAt)
            reset = L10n.resetLabel(relativeTo: date)
        } else if let after = doubleValue(window["reset_after_seconds"]) {
            let date = Date().addingTimeInterval(after)
            reset = L10n.resetLabel(relativeTo: date)
        } else {
            reset = nil
        }

        return LimitRow(
            id: id,
            title: title(forWindow: window, fallback: fallbackTitle, prefix: prefix),
            detail: detail,
            percentUsed: used,
            remainingLabel: remaining,
            resetLabel: reset
        )
    }

    /// Detect the window kind from `limit_window_seconds` (Team plans use a
    /// weekly primary window, so `primary = 5h` must not be assumed).
    private static func title(forWindow window: [String: Any], fallback: String, prefix: String? = nil) -> String {
        let kind: String
        switch intValue(window["limit_window_seconds"]) {
        case 18_000: kind = L10n.tr("limit.window_5h")
        case 604_800: kind = L10n.tr("limit.week")
        case 2_592_000: kind = L10n.tr("limit.month")
        default: kind = fallback
        }
        if let prefix, !prefix.isEmpty { return "\(prefix) · \(kind)" }
        return kind
    }

    private static func doubleValue(_ any: Any?) -> Double? {
        switch any {
        case let d as Double: return d
        case let i as Int: return Double(i)
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }

    private static func intValue(_ any: Any?) -> Int? {
        switch any {
        case let i as Int: return i
        case let n as NSNumber: return n.intValue
        case let s as String: return Int(s)
        default: return nil
        }
    }
}

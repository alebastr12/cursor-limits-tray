import Foundation

enum ChatGPTUsageClient {
    struct Auth {
        var sessionCookie: String?
        var bearerToken: String?
    }

    static func fetch(auth: Auth) async throws -> ProviderSnapshot {
        let bearer: String
        if let override = auth.bearerToken?.trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            bearer = override.hasPrefix("Bearer ") ? String(override.dropFirst(7)) : override
        } else if let cookie = auth.sessionCookie?.trimmingCharacters(in: .whitespacesAndNewlines), !cookie.isEmpty {
            bearer = try await exchangeSessionCookie(normalizeCookie(cookie))
        } else {
            throw UsageError.notConfigured("Paste your ChatGPT session cookie in Settings.")
        }

        let json = try await getJSON(
            url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
            headers: [
                "Authorization": "Bearer \(bearer)",
                "User-Agent": "Mozilla/5.0 CursorLimitsTray/0.1",
                "Accept": "application/json"
            ]
        )
        return mapUsage(json)
    }

    private static func normalizeCookie(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("cookie:") {
            return String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        }
        if trimmed.contains("=") { return trimmed }
        // bare token → single session cookie name
        return "__Secure-next-auth.session-token=\(trimmed)"
    }

    private static func exchangeSessionCookie(_ cookie: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://chatgpt.com/api/auth/session")!)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("Mozilla/5.0 CursorLimitsTray/0.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UsageError.badResponse }
        guard http.statusCode == 200 else {
            throw UsageError.http(http.statusCode, String(data: data, encoding: .utf8))
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let token = json["accessToken"] as? String, !token.isEmpty else {
            throw UsageError.auth("ChatGPT session cookie did not yield an accessToken. Re-copy cookies from chatgpt.com.")
        }
        return token
    }

    private static func getJSON(url: URL, headers: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UsageError.badResponse }
        guard http.statusCode == 200 else {
            throw UsageError.http(http.statusCode, String(data: data, encoding: .utf8))
        }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func mapUsage(_ json: [String: Any]) -> ProviderSnapshot {
        // Responses vary: sometimes nested under "usage", sometimes top-level rate_limit.
        let root = (json["usage"] as? [String: Any]) ?? json
        let planType = (root["plan_type"] as? String) ?? (json["plan_type"] as? String) ?? "ChatGPT"
        let rate = (root["rate_limit"] as? [String: Any]) ?? [:]

        var rows: [LimitRow] = []
        if let primary = rate["primary_window"] as? [String: Any] {
            rows.append(windowRow(id: "cgpt-primary", title: L10n.tr("limit.window_5h"), detail: L10n.tr("limit.primary"), window: primary))
        }
        if let secondary = rate["secondary_window"] as? [String: Any] {
            rows.append(windowRow(id: "cgpt-secondary", title: L10n.tr("limit.week"), detail: L10n.tr("limit.secondary"), window: secondary))
        }
        if let extras = rate["additional_rate_limits"] as? [[String: Any]] {
            for (idx, extra) in extras.enumerated() {
                let name = (extra["feature_name"] as? String)
                    ?? (extra["name"] as? String)
                    ?? "Extra limit \(idx + 1)"
                rows.append(windowRow(id: "cgpt-extra-\(idx)", title: name, detail: "Additional limit", window: extra))
            }
        }

        if let credits = root["credits"] as? [String: Any] {
            let unlimited = credits["unlimited"] as? Bool ?? false
            let balance = credits["balance"]
            let balanceText: String
            if unlimited {
                balanceText = "Unlimited"
            } else if let s = balance as? String {
                balanceText = s
            } else if let n = balance as? NSNumber {
                balanceText = n.stringValue
            } else {
                balanceText = "—"
            }
            if credits["has_credits"] as? Bool == true || unlimited {
                rows.append(
                    LimitRow(
                        id: "cgpt-credits",
                        title: "Credits",
                        detail: "Account credit balance",
                        percentUsed: nil,
                        remainingLabel: balanceText,
                        resetLabel: nil
                    )
                )
            }
        }

        return ProviderSnapshot(
            name: "ChatGPT",
            status: planType.capitalized,
            rows: rows,
            fetchedAt: Date(),
            error: rows.isEmpty ? "wham/usage returned no rate_limit windows" : nil
        )
    }

    private static func windowRow(id: String, title: String, detail: String, window: [String: Any]) -> LimitRow {
        let used = doubleValue(window["used_percent"]) ?? doubleValue(window["usedPercent"])
        let remaining: String?
        if let used {
            remaining = L10n.remainingPercent(max(0, 100 - used))
        } else if let rem = doubleValue(window["remaining"]) {
            remaining = String(format: "%.0f remaining", rem)
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
            title: title,
            detail: detail,
            percentUsed: used,
            remainingLabel: remaining,
            resetLabel: reset
        )
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
}

enum UsageError: LocalizedError {
    case notConfigured(String)
    case auth(String)
    case http(Int, String?)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured(let msg): return msg
        case .auth(let msg): return msg
        case .http(let code, let body):
            let snippet = body.flatMap { String($0.prefix(160)) } ?? ""
            return "HTTP \(code)\(snippet.isEmpty ? "" : ": \(snippet)")"
        case .badResponse: return "Unexpected response"
        }
    }
}

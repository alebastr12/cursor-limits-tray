import Foundation

enum ClaudeUsageClient {
    struct Auth {
        var sessionCookie: String?
        var bearerToken: String?
    }

    static func fetch(auth: Auth) async throws -> ProviderSnapshot {
        if let bearer = auth.bearerToken?.trimmingCharacters(in: .whitespacesAndNewlines), !bearer.isEmpty {
            if let snap = try? await fetchViaOAuth(bearer: bearer) {
                return snap
            }
        }
        let cookie = normalizeCookie(auth.sessionCookie)
        guard let cookie, !cookie.isEmpty else {
            throw UsageError.notConfigured(L10n.tr("error.connect_claude_or_app"))
        }
        return try await fetchViaWeb(cookie: cookie)
    }

    private static func normalizeCookie(_ raw: String?) -> String? {
        guard var trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        if trimmed.lowercased().hasPrefix("cookie:") {
            trimmed = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        }
        if trimmed.contains("=") { return trimmed }
        return "sessionKey=\(trimmed)"
    }

    // MARK: - Web (claude.ai)

    private static func fetchViaWeb(cookie: String) async throws -> ProviderSnapshot {
        let headers = [
            "Cookie": cookie,
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15 CursorLimitsTray/0.2",
            "Accept": "application/json",
            "Referer": "https://claude.ai/settings/usage",
            "Origin": "https://claude.ai"
        ]
        let orgs = try await getJSON(url: URL(string: "https://claude.ai/api/organizations")!, headers: headers)
        let orgList: [[String: Any]]
        if let arr = orgs as? [[String: Any]] {
            orgList = arr
        } else if let dict = orgs as? [String: Any], let arr = dict["data"] as? [[String: Any]] {
            orgList = arr
        } else {
            throw UsageError.auth(L10n.tr("error.claude_orgs_read"))
        }
        guard !orgList.isEmpty else {
            throw UsageError.auth(L10n.tr("error.claude_no_orgs"))
        }

        // Prefer an org that actually reports usage windows.
        var bestUsage: [String: Any] = [:]
        var bestOrg: [String: Any] = orgList[0]
        for org in orgList {
            guard let uuid = (org["uuid"] as? String) ?? (org["id"] as? String) else { continue }
            let usage = try await getDict(
                url: URL(string: "https://claude.ai/api/organizations/\(uuid)/usage")!,
                headers: headers
            )
            if hasUsageSignal(usage) {
                bestUsage = usage
                bestOrg = org
                break
            }
            if bestUsage.isEmpty {
                bestUsage = usage
                bestOrg = org
            }
        }

        let plan = (bestOrg["plan_display_name"] as? String)
            ?? (bestOrg["analytics_subscription_plan"] as? String)
            ?? (bestOrg["rate_limit_tier"] as? String)
            ?? "Claude"
        return mapUsage(bestUsage, planLabel: humanPlan(plan))
    }

    // MARK: - OAuth (Claude Code)

    private static func fetchViaOAuth(bearer: String) async throws -> ProviderSnapshot {
        let token = bearer.hasPrefix("Bearer ") ? String(bearer.dropFirst(7)) : bearer
        let json = try await getDict(
            url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
            headers: [
                "Authorization": "Bearer \(token)",
                "anthropic-beta": "oauth-2025-04-20",
                "Accept": "application/json",
                "User-Agent": "CursorLimitsTray/0.2"
            ]
        )
        return mapUsage(json, planLabel: "Claude Code")
    }

    // MARK: - Mapping

    private static func hasUsageSignal(_ json: [String: Any]) -> Bool {
        if let five = json["five_hour"] as? [String: Any], five["utilization"] != nil { return true }
        if let week = json["seven_day"] as? [String: Any], week["utilization"] != nil { return true }
        if let limits = json["limits"] as? [[String: Any]], !limits.isEmpty { return true }
        return false
    }

    private static func mapUsage(_ json: [String: Any], planLabel: String) -> ProviderSnapshot {
        var rows: [LimitRow] = []

        if let five = json["five_hour"] as? [String: Any] {
            rows.append(windowRow(id: "claude-5h", title: L10n.tr("limit.window_5h"), detail: L10n.tr("limit.session_rate"), window: five))
        }
        if let week = json["seven_day"] as? [String: Any] {
            rows.append(windowRow(id: "claude-7d", title: L10n.tr("limit.week"), detail: L10n.tr("limit.weekly_rate"), window: week))
        }
        if let opus = json["seven_day_opus"] as? [String: Any], opus["utilization"] != nil {
            rows.append(windowRow(id: "claude-opus", title: L10n.tr("limit.opus_week"), detail: "Model-scoped weekly", window: opus))
        }
        if let sonnet = json["seven_day_sonnet"] as? [String: Any], sonnet["utilization"] != nil {
            rows.append(windowRow(id: "claude-sonnet", title: L10n.tr("limit.sonnet_week"), detail: "Model-scoped weekly", window: sonnet))
        }
        if let limits = json["limits"] as? [[String: Any]] {
            for (idx, lim) in limits.enumerated() {
                let kind = (lim["kind"] as? String) ?? "limit-\(idx)"
                let title: String
                switch kind {
                case "session": title = L10n.tr("limit.session")
                case "weekly_all": title = L10n.tr("limit.week")
                case "weekly_scoped": title = L10n.tr("limit.week_model")
                default: title = kind
                }
                if let pct = doubleValue(lim["percent"]) ?? doubleValue(lim["utilization"]) {
                    rows.append(
                        LimitRow(
                            id: "claude-lim-\(idx)",
                            title: title,
                            detail: kind,
                            percentUsed: pct,
                            remainingLabel: L10n.remainingPercent(max(0, 100 - pct)),
                            resetLabel: resetLabel(iso: lim["resets_at"] as? String)
                        )
                    )
                }
            }
        }

        if rows.isEmpty {
            return ProviderSnapshot(
                name: "Claude",
                status: L10n.connectedWithDetail(planLabel),
                rows: [
                    LimitRow(
                        id: "claude-empty",
                        title: L10n.tr("limit.five_week_combo"),
                        detail: L10n.tr("limit.claude_empty_detail"),
                        percentUsed: nil,
                        remainingLabel: nil,
                        resetLabel: nil
                    )
                ],
                fetchedAt: Date(),
                error: nil
            )
        }

        return ProviderSnapshot(
            name: "Claude",
            status: planLabel,
            rows: rows,
            fetchedAt: Date(),
            error: nil
        )
    }

    private static func windowRow(id: String, title: String, detail: String, window: [String: Any]) -> LimitRow {
        let used = doubleValue(window["utilization"])
        let remaining = used.map { L10n.remainingPercent(max(0, 100 - $0)) }
        return LimitRow(
            id: id,
            title: title,
            detail: detail,
            percentUsed: used,
            remainingLabel: remaining,
            resetLabel: resetLabel(iso: window["resets_at"] as? String)
        )
    }

    private static func resetLabel(iso: String?) -> String? {
        guard let iso else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = f.date(from: iso)
        if date == nil {
            f.formatOptions = [.withInternetDateTime]
            date = f.date(from: iso)
        }
        guard let date else { return nil }
        return L10n.resetLabel(relativeTo: date)
    }

    private static func humanPlan(_ raw: String) -> String {
        switch raw {
        case "claude_free", "default_claude_ai": return "Free"
        case "claude_pro": return "Pro"
        case "claude_max", "claude_max_5x", "claude_max_20x": return "Max"
        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private static func getJSON(url: URL, headers: [String: String]) async throws -> Any {
        var request = URLRequest(url: url)
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UsageError.badResponse }
        guard http.statusCode == 200 else {
            throw UsageError.http(http.statusCode, String(data: data, encoding: .utf8))
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    private static func getDict(url: URL, headers: [String: String]) async throws -> [String: Any] {
        let any = try await getJSON(url: url, headers: headers)
        return (any as? [String: Any]) ?? [:]
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

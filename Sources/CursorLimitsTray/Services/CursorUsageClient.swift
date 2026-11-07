import Foundation

enum CursorUsageClient {
    struct Auth {
        var bearerToken: String?
        var sessionCookie: String?
        var userId: String?
    }

    static func fetch(auth: Auth) async throws -> ProviderSnapshot {
        if let bearer = auth.bearerToken, !bearer.isEmpty {
            if let snap = try? await fetchViaDashboard(bearer: bearer) {
                return snap
            }
            if let snap = try? await fetchViaUsageSummary(cookie: cookieHeader(userId: auth.userId, token: bearer)) {
                return snap
            }
        }
        if let cookie = auth.sessionCookie, !cookie.isEmpty {
            return try await fetchViaUsageSummary(cookie: normalizeCookie(cookie))
        }
        throw UsageError.notConfigured("Add a Cursor session cookie in Settings, or sign in to the Cursor app on this Mac.")
    }

    private static func cookieHeader(userId: String?, token: String) -> String {
        if let userId, !userId.isEmpty {
            let encoded = "\(userId)::\(token)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "\(userId)%3A%3A\(token)"
            // Prefer explicit %3A%3A form used by Cursor web
            let value = "\(userId)%3A%3A\(token)"
            _ = encoded
            return "WorkosCursorSessionToken=\(value)"
        }
        return "WorkosCursorSessionToken=\(token)"
    }

    private static func normalizeCookie(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("cookie:") {
            return String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        }
        if trimmed.contains("=") { return trimmed }
        return "WorkosCursorSessionToken=\(trimmed)"
    }

    private static func fetchViaDashboard(bearer: String) async throws -> ProviderSnapshot {
        async let period = postJSON(
            url: URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!,
            bearer: bearer,
            body: [:]
        )
        async let sand = postJSON(
            url: URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetSandUsageStatus")!,
            bearer: bearer,
            body: [:]
        )
        async let plan = postJSON(
            url: URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetPlanInfo")!,
            bearer: bearer,
            body: [:]
        )

        let periodJSON = try await period
        let sandJSON = (try? await sand) ?? [:]
        let planJSON = (try? await plan) ?? [:]

        return mapDashboard(period: periodJSON, sand: sandJSON, plan: planJSON)
    }

    private static func fetchViaUsageSummary(cookie: String) async throws -> ProviderSnapshot {
        var request = URLRequest(url: URL(string: "https://cursor.com/api/usage-summary")!)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X) CursorLimitsTray/0.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UsageError.badResponse }
        guard http.statusCode == 200 else {
            throw UsageError.http(http.statusCode, String(data: data, encoding: .utf8))
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return mapUsageSummary(json)
    }

    private static func postJSON(url: URL, bearer: String, body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue("Mozilla/5.0 CursorLimitsTray/0.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UsageError.badResponse }
        guard http.statusCode == 200 else {
            throw UsageError.http(http.statusCode, String(data: data, encoding: .utf8))
        }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func mapDashboard(period: [String: Any], sand: [String: Any], plan: [String: Any]) -> ProviderSnapshot {
        let planUsage = period["planUsage"] as? [String: Any] ?? [:]
        let totalPercent = doubleValue(planUsage["totalPercentUsed"]) ?? doubleValue(sand["usagePercent"])
        let planInfo = plan["planInfo"] as? [String: Any] ?? [:]
        let planName = (planInfo["planName"] as? String)
            ?? (sand["cursorPlanName"] as? String)
            ?? "Cursor"
        let isUnified = sand["isUnified"] as? Bool ?? false

        var rows: [LimitRow] = []
        if let totalPercent {
            rows.append(
                LimitRow(
                    id: "cursor-included",
                    title: isUnified ? "Недельный пул" : "Включённое использование",
                    detail: (period["displayMessage"] as? String) ?? (sand["displayMessage"] as? String) ?? "Лимит плана",
                    percentUsed: totalPercent,
                    remainingLabel: String(format: "%.0f%% осталось", max(0, 100 - totalPercent)),
                    resetLabel: resetLabel(
                        fromISO: sand["nextResetTimestampUtc"] as? String,
                        fromMillis: int64Value(planInfo["includedUsageResetsAt"]) ?? int64Value(period["billingCycleEnd"])
                    )
                )
            )
        }

        if let auto = doubleValue(planUsage["autoPercentUsed"]), abs(auto - (totalPercent ?? -1)) > 0.5 {
            rows.append(
                LimitRow(
                    id: "cursor-auto",
                    title: "Cursor models",
                    detail: "Auto / first-party pool",
                    percentUsed: auto,
                    remainingLabel: String(format: "%.0f%% осталось", max(0, 100 - auto)),
                    resetLabel: nil
                )
            )
        }
        if let api = doubleValue(planUsage["apiPercentUsed"]) {
            rows.append(
                LimitRow(
                    id: "cursor-api",
                    title: "Other models",
                    detail: "Third-party / API pool",
                    percentUsed: api,
                    remainingLabel: String(format: "%.0f%% осталось", max(0, 100 - api)),
                    resetLabel: nil
                )
            )
        }

        let statusBits = [planName, isUnified ? "X Subscription" : nil].compactMap { $0 }
        return ProviderSnapshot(
            name: "Cursor",
            status: statusBits.joined(separator: " · "),
            rows: rows,
            fetchedAt: Date(),
            error: rows.isEmpty ? "No usage fields in response" : nil
        )
    }

    private static func mapUsageSummary(_ json: [String: Any]) -> ProviderSnapshot {
        let membership = json["membershipType"] as? String ?? "Cursor"
        let individual = json["individualUsage"] as? [String: Any] ?? [:]
        let plan = individual["plan"] as? [String: Any] ?? [:]
        let used = doubleValue(plan["used"])
        let limit = doubleValue(plan["limit"])
        let remaining = doubleValue(plan["remaining"])
        let totalPercent = doubleValue(plan["totalPercentUsed"])
        let cycleEnd = json["billingCycleEnd"] as? String

        var rows: [LimitRow] = []
        if let totalPercent {
            rows.append(
                LimitRow(
                    id: "cursor-plan-pct",
                    title: "Plan usage",
                    detail: (json["autoModelSelectedDisplayMessage"] as? String) ?? "Included allowance",
                    percentUsed: totalPercent,
                    remainingLabel: String(format: "%.0f%% осталось", max(0, 100 - totalPercent)),
                    resetLabel: resetLabel(fromISO: cycleEnd, fromMillis: nil)
                )
            )
        } else if let used, let limit, limit > 0 {
            let pct = used / limit * 100
            rows.append(
                LimitRow(
                    id: "cursor-plan-count",
                    title: "Plan requests",
                    detail: "used \(Int(used)) / \(Int(limit))",
                    percentUsed: pct,
                    remainingLabel: remaining.map { "\(Int($0)) left" },
                    resetLabel: resetLabel(fromISO: cycleEnd, fromMillis: nil)
                )
            )
        }

        return ProviderSnapshot(
            name: "Cursor",
            status: membership.capitalized,
            rows: rows,
            fetchedAt: Date(),
            error: rows.isEmpty ? "Empty usage-summary" : nil
        )
    }

    private static func resetLabel(fromISO iso: String?, fromMillis millis: Int64?) -> String? {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        if let iso,
           let date = ISO8601DateFormatter().date(from: iso)
            ?? ISO8601DateFormatter.fullFractional.date(from: iso) {
            return "Resets \(formatter.localizedString(for: date, relativeTo: Date()))"
        }
        if let millis {
            // Cursor sometimes returns ms as stringified numbers that are actually epoch-ms-like ids;
            // only treat as epoch if looks like a real timestamp (~1e12..1e13).
            if millis > 1_000_000_000_000, millis < 10_000_000_000_000 {
                let date = Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
                return "Resets \(formatter.localizedString(for: date, relativeTo: Date()))"
            }
        }
        return nil
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

    private static func int64Value(_ any: Any?) -> Int64? {
        switch any {
        case let i as Int64: return i
        case let i as Int: return Int64(i)
        case let n as NSNumber: return n.int64Value
        case let s as String: return Int64(s)
        default: return nil
        }
    }
}

private extension ISO8601DateFormatter {
    static let fullFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

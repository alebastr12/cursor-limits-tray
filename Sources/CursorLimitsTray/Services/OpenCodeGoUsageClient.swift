import Foundation

/// OpenCode Go subscription windows.
/// `GET https://opencode.ai/zen/go/v1/usage` returns:
/// { "usage": { "rolling": {percent,status,resetsAt}, "weekly": ..., "monthly": ... } }
enum OpenCodeGoUsageClient {
    struct Auth {
        var apiKey: String?
    }

    private static let usageURL = URL(string: "https://opencode.ai/zen/go/v1/usage")!

    static func fetch(auth: Auth) async throws -> ProviderSnapshot {
        let key = auth.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty else {
            throw UsageError.notConfigured(L10n.tr("error.opencode_key_missing"))
        }

        var request = URLRequest(url: usageURL)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("TrayAILimits/0.1", forHTTPHeaderField: "User-Agent")

        do {
            let object = try await HTTPClient.json(for: request)
            guard let root = object as? [String: Any],
                  let usage = root["usage"] as? [String: Any]
            else { throw UsageError.badResponse }
            return mapUsage(usage)
        } catch let error as UsageError {
            if case .http(let code, _) = error, code == 401 || code == 403 {
                throw UsageError.auth(L10n.tr("error.opencode_auth"))
            }
            throw error
        }
    }

    /// Internal for parser tests (`@testable import`).
    static func mapUsage(_ usage: [String: Any]) -> ProviderSnapshot {
        var rows: [LimitRow] = []

        func append(_ key: String, id: String, title: String, detail: String) {
            guard let window = usage[key] as? [String: Any],
                  let raw = doubleValue(window["percent"])
            else { return }
            let used = min(max(raw, 0), 100)
            rows.append(
                LimitRow(
                    id: id,
                    title: title,
                    detail: detail,
                    percentUsed: used,
                    remainingLabel: L10n.remainingPercent(100 - used),
                    resetLabel: resetLabel(window["resetsAt"] as? String)
                )
            )
        }

        append("rolling", id: "opencode-5h",
               title: L10n.tr("limit.window_5h"),
               detail: L10n.tr("limit.rolling_5h"))
        append("weekly", id: "opencode-week",
               title: L10n.tr("limit.week"),
               detail: L10n.tr("limit.weekly_rate"))
        append("monthly", id: "opencode-month",
               title: L10n.tr("limit.month"),
               detail: L10n.tr("limit.monthly"))

        return ProviderSnapshot(
            name: "OpenCode Go",
            status: "OpenCode Go",
            rows: rows,
            fetchedAt: Date(),
            error: rows.isEmpty ? L10n.tr("error.opencode_no_windows") : nil
        )
    }

    private static func resetLabel(_ iso: String?) -> String? {
        guard let iso else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: iso)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: iso)
        }
        guard let date else { return nil }
        return L10n.resetLabel(relativeTo: date)
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

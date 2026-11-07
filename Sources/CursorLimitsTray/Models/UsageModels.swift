import Foundation

struct LimitRow: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let percentUsed: Double?
    let remainingLabel: String?
    let resetLabel: String?
}

struct ProviderSnapshot: Equatable {
    var name: String
    var status: String
    var rows: [LimitRow]
    var fetchedAt: Date?
    var error: String?
}

struct UsageSnapshot: Equatable {
    var cursor: ProviderSnapshot
    var chatGPT: ProviderSnapshot
    var isDemo: Bool

    static let empty = UsageSnapshot(
        cursor: ProviderSnapshot(name: "Cursor", status: "Not configured", rows: [], fetchedAt: nil, error: nil),
        chatGPT: ProviderSnapshot(name: "ChatGPT", status: "Not configured", rows: [], fetchedAt: nil, error: nil),
        isDemo: false
    )

    static let demo: UsageSnapshot = {
        let now = Date()
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let weeklyReset = now.addingTimeInterval(60 * 60 * 36)
        let fiveHourReset = now.addingTimeInterval(60 * 95)
        return UsageSnapshot(
            cursor: ProviderSnapshot(
                name: "Cursor",
                status: "Premium · demo",
                rows: [
                    LimitRow(
                        id: "cursor-weekly",
                        title: "Weekly pool",
                        detail: "Included Cursor / Grok usage",
                        percentUsed: 21,
                        remainingLabel: "79% left",
                        resetLabel: "Resets \(formatter.localizedString(for: weeklyReset, relativeTo: now))"
                    ),
                    LimitRow(
                        id: "cursor-cycle",
                        title: "Billing window",
                        detail: "Weekly included period",
                        percentUsed: nil,
                        remainingLabel: nil,
                        resetLabel: "Next reset Thu 19:19"
                    )
                ],
                fetchedAt: now,
                error: nil
            ),
            chatGPT: ProviderSnapshot(
                name: "ChatGPT",
                status: "Plus · demo",
                rows: [
                    LimitRow(
                        id: "cgpt-5h",
                        title: "5-hour window",
                        detail: "Primary rate limit",
                        percentUsed: 33,
                        remainingLabel: "67% left",
                        resetLabel: "Resets \(formatter.localizedString(for: fiveHourReset, relativeTo: now))"
                    ),
                    LimitRow(
                        id: "cgpt-week",
                        title: "Weekly window",
                        detail: "Secondary rate limit",
                        percentUsed: 12,
                        remainingLabel: "88% left",
                        resetLabel: "Resets in 5d"
                    )
                ],
                fetchedAt: now,
                error: nil
            ),
            isDemo: true
        )
    }()
}

enum AppPreferences {
    static let pollIntervalKey = "pollIntervalSeconds"
    static let demoModeKey = "forceDemoMode"
    static let openAtLoginKey = "openAtLogin"

    static var pollIntervalSeconds: Double {
        get {
            let stored = UserDefaults.standard.object(forKey: pollIntervalKey) as? Double
            return stored ?? 45
        }
        set {
            UserDefaults.standard.set(max(15, min(newValue, 600)), forKey: pollIntervalKey)
        }
    }

    static var forceDemoMode: Bool {
        get { UserDefaults.standard.bool(forKey: demoModeKey) }
        set { UserDefaults.standard.set(newValue, forKey: demoModeKey) }
    }
}

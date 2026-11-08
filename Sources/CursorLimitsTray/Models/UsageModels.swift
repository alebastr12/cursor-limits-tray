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
    var claude: ProviderSnapshot
    var isDemo: Bool

    static let empty = UsageSnapshot(
        cursor: ProviderSnapshot(name: "Cursor", status: "—", rows: [], fetchedAt: nil, error: nil),
        chatGPT: ProviderSnapshot(name: "ChatGPT", status: "—", rows: [], fetchedAt: nil, error: nil),
        claude: ProviderSnapshot(name: "Claude", status: "—", rows: [], fetchedAt: nil, error: nil),
        isDemo: false
    )

    static var demo: UsageSnapshot {
        let now = Date()
        let weeklyReset = now.addingTimeInterval(60 * 60 * 36)
        let fiveHourReset = now.addingTimeInterval(60 * 95)
        return UsageSnapshot(
            cursor: ProviderSnapshot(
                name: "Cursor",
                status: "Premium · demo",
                rows: [
                    LimitRow(
                        id: "c1",
                        title: L10n.tr("limit.weekly_pool"),
                        detail: "Cursor / Grok",
                        percentUsed: 21,
                        remainingLabel: L10n.remainingPercent(79),
                        resetLabel: L10n.resetLabel(relativeTo: weeklyReset, now: now)
                    )
                ],
                fetchedAt: now, error: nil
            ),
            chatGPT: ProviderSnapshot(
                name: "ChatGPT",
                status: "Plus · demo",
                rows: [
                    LimitRow(
                        id: "g1",
                        title: L10n.tr("limit.window_5h"),
                        detail: "Primary",
                        percentUsed: 33,
                        remainingLabel: L10n.remainingPercent(67),
                        resetLabel: L10n.resetLabel(relativeTo: fiveHourReset, now: now)
                    ),
                    LimitRow(
                        id: "g2",
                        title: L10n.tr("limit.week"),
                        detail: "Secondary",
                        percentUsed: 12,
                        remainingLabel: L10n.remainingPercent(88),
                        resetLabel: nil
                    )
                ],
                fetchedAt: now, error: nil
            ),
            claude: ProviderSnapshot(
                name: "Claude",
                status: "Pro · demo",
                rows: [
                    LimitRow(
                        id: "a1",
                        title: L10n.tr("limit.window_5h"),
                        detail: "Session",
                        percentUsed: 40,
                        remainingLabel: L10n.remainingPercent(60),
                        resetLabel: L10n.resetLabel(relativeTo: fiveHourReset, now: now)
                    ),
                    LimitRow(
                        id: "a2",
                        title: L10n.tr("limit.week"),
                        detail: "Weekly",
                        percentUsed: 25,
                        remainingLabel: L10n.remainingPercent(75),
                        resetLabel: nil
                    )
                ],
                fetchedAt: now, error: nil
            ),
            isDemo: true
        )
    }
}

enum AppPreferences {
    static let pollIntervalKey = "pollIntervalSeconds"
    static let demoModeKey = "forceDemoMode"

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

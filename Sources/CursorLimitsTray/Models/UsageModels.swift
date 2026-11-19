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
    var openCodeGo: ProviderSnapshot
    var isDemo: Bool

    static let empty = UsageSnapshot(
        cursor: ProviderSnapshot(name: "Cursor", status: "—", rows: [], fetchedAt: nil, error: nil),
        chatGPT: ProviderSnapshot(name: "ChatGPT", status: "—", rows: [], fetchedAt: nil, error: nil),
        claude: ProviderSnapshot(name: "Claude", status: "—", rows: [], fetchedAt: nil, error: nil),
        openCodeGo: ProviderSnapshot(name: "OpenCode Go", status: "—", rows: [], fetchedAt: nil, error: nil),
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
                    ),
                    LimitRow(
                        id: "c2",
                        title: "Other models",
                        detail: "Third-party / API pool",
                        percentUsed: 44,
                        remainingLabel: L10n.remainingPercent(56),
                        resetLabel: nil
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
            openCodeGo: ProviderSnapshot(
                name: "OpenCode Go",
                status: "Go · demo",
                rows: [
                    LimitRow(
                        id: "o1",
                        title: L10n.tr("limit.window_5h"),
                        detail: L10n.tr("limit.rolling_5h"),
                        percentUsed: 16,
                        remainingLabel: L10n.remainingPercent(84),
                        resetLabel: L10n.resetLabel(relativeTo: fiveHourReset, now: now)
                    ),
                    LimitRow(
                        id: "o2",
                        title: L10n.tr("limit.week"),
                        detail: L10n.tr("limit.weekly_rate"),
                        percentUsed: 11,
                        remainingLabel: L10n.remainingPercent(89),
                        resetLabel: nil
                    ),
                    LimitRow(
                        id: "o3",
                        title: L10n.tr("limit.month"),
                        detail: L10n.tr("limit.monthly"),
                        percentUsed: 5,
                        remainingLabel: L10n.remainingPercent(95),
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
    static let lowBalanceNotificationsKey = "lowBalanceNotifications"
    static let autoUpdateKey = "autoUpdateEnabled"
    static let lastUpdateCheckKey = "lastUpdateCheck"

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

    static var lowBalanceNotificationsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: lowBalanceNotificationsKey) }
        set { UserDefaults.standard.set(newValue, forKey: lowBalanceNotificationsKey) }
    }

    /// Opt-out: enabled by default as requested.
    static var autoUpdateEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: autoUpdateKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: autoUpdateKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: autoUpdateKey) }
    }

    static var lastUpdateCheck: Date? {
        get { UserDefaults.standard.object(forKey: lastUpdateCheckKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastUpdateCheckKey) }
    }
}

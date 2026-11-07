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

    static let demo: UsageSnapshot = {
        let now = Date()
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.unitsStyle = .abbreviated
        let weeklyReset = now.addingTimeInterval(60 * 60 * 36)
        let fiveHourReset = now.addingTimeInterval(60 * 95)
        return UsageSnapshot(
            cursor: ProviderSnapshot(
                name: "Cursor",
                status: "Premium · demo",
                rows: [
                    LimitRow(id: "c1", title: "Недельный пул", detail: "Cursor / Grok", percentUsed: 21, remainingLabel: "79% осталось", resetLabel: "Сброс \(formatter.localizedString(for: weeklyReset, relativeTo: now))")
                ],
                fetchedAt: now, error: nil
            ),
            chatGPT: ProviderSnapshot(
                name: "ChatGPT",
                status: "Plus · demo",
                rows: [
                    LimitRow(id: "g1", title: "Окно 5 часов", detail: "Primary", percentUsed: 33, remainingLabel: "67% осталось", resetLabel: "Сброс \(formatter.localizedString(for: fiveHourReset, relativeTo: now))"),
                    LimitRow(id: "g2", title: "Неделя", detail: "Secondary", percentUsed: 12, remainingLabel: "88% осталось", resetLabel: nil)
                ],
                fetchedAt: now, error: nil
            ),
            claude: ProviderSnapshot(
                name: "Claude",
                status: "Pro · demo",
                rows: [
                    LimitRow(id: "a1", title: "Окно 5 часов", detail: "Session", percentUsed: 40, remainingLabel: "60% осталось", resetLabel: "Сброс \(formatter.localizedString(for: fiveHourReset, relativeTo: now))"),
                    LimitRow(id: "a2", title: "Неделя", detail: "Weekly", percentUsed: 25, remainingLabel: "75% осталось", resetLabel: nil)
                ],
                fetchedAt: now, error: nil
            ),
            isDemo: true
        )
    }()
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

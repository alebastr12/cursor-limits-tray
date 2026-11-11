import Foundation

/// One live usage meter in the menu bar (icon shown once per contiguous provider group).
struct MenuBarSegment: Equatable {
    enum Provider: Equatable {
        case cursor
        case chatGPT
        case claude

        /// Template PNG in Resources/MenuBarProviders (not SF Symbol).
        var resourceName: String {
            switch self {
            case .cursor: return "ProviderCursor"
            case .chatGPT: return "ProviderChatGPT"
            case .claude: return "ProviderClaude"
            }
        }

        var accessibilityName: String {
            switch self {
            case .cursor: return "Cursor"
            case .chatGPT: return "ChatGPT"
            case .claude: return "Claude"
            }
        }
    }

    let provider: Provider
    let remainingPercent: Int
    let severity: LimitSeverity
    /// Short localized kind for hover tip (5-hour / weekly / monthly), or provider row title.
    let kindLabel: String
}

/// Maps provider row titles onto the short tip kinds the product asks for.
enum LimitKindLabel {
    static func tooltipLabel(forRowTitle title: String) -> String {
        if matches(title, keys: [
            "limit.window_5h",
            "limit.session",
            "limit.session_rate"
        ]) || fuzzyFiveHour(title) {
            return L10n.tr("tooltip.kind.5h")
        }
        if matches(title, keys: [
            "limit.month",
            "limit.monthly",
            "limit.monthly_pool"
        ]) || fuzzyMonthly(title) {
            return L10n.tr("tooltip.kind.monthly")
        }
        if matches(title, keys: [
            "limit.week",
            "limit.week_model",
            "limit.weekly_pool",
            "limit.weekly_rate",
            "limit.opus_week",
            "limit.sonnet_week"
        ]) || fuzzyWeekly(title) {
            return L10n.tr("tooltip.kind.weekly")
        }
        // Prefer the real provider label when it is not a clear 5h / week / month bucket.
        return title
    }

    private static func matches(_ title: String, keys: [String]) -> Bool {
        keys.contains { L10n.tr($0) == title }
    }

    private static func fuzzyFiveHour(_ title: String) -> Bool {
        let t = title.lowercased()
        return t.contains("5-hour")
            || t.contains("5 hour")
            || t.contains("5h")
            || t.contains("5ч")
            || t.contains("5 ч")
            || (t.contains("5") && (t.contains("hour") || t.contains("час")))
    }

    private static func fuzzyWeekly(_ title: String) -> Bool {
        let t = title.lowercased()
        return t.contains("week")
            || t.contains("недел")
            || t.contains("7-day")
            || t.contains("7 day")
            || t.contains("seven_day")
    }

    private static func fuzzyMonthly(_ title: String) -> Bool {
        let t = title.lowercased()
        return t.contains("month") || t.contains("месяц")
    }
}

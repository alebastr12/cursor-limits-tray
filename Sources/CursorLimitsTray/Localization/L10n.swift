import Foundation

/// UI copy follows macOS interface language via `Localizable.strings` (en + ru).
/// Resolves catalogs from `Locale.preferredLanguages` (not hardcoded Russian).
enum L10n {
    static var locale: Locale { .autoupdatingCurrent }

    /// Bundle whose `Localizable.strings` match the top preferred language we ship.
    private static var stringsBundle: Bundle {
        let available = ["en", "ru"]
        for preferred in Locale.preferredLanguages {
            let raw = preferred.lowercased()
            let code: String
            if raw.hasPrefix("ru") {
                code = "ru"
            } else if raw.hasPrefix("en") {
                code = "en"
            } else if let dash = raw.firstIndex(of: "-") {
                code = String(raw[..<dash])
            } else if let under = raw.firstIndex(of: "_") {
                code = String(raw[..<under])
            } else {
                code = String(raw.prefix(2))
            }
            guard available.contains(code),
                  let path = Bundle.main.path(forResource: code, ofType: "lproj"),
                  let bundle = Bundle(path: path)
            else { continue }
            return bundle
        }
        if let path = Bundle.main.path(forResource: "en", ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return .main
    }

    static func tr(_ key: String) -> String {
        NSLocalizedString(key, tableName: "Localizable", bundle: stringsBundle, value: key, comment: "")
    }

    static func tr(_ key: String, _ args: CVarArg...) -> String {
        let format = tr(key)
        return String(format: format, locale: locale, arguments: args)
    }

    static var relativeDateFormatter: RelativeDateTimeFormatter {
        let f = RelativeDateTimeFormatter()
        f.locale = locale
        f.unitsStyle = .abbreviated
        return f
    }

    // MARK: - Common

    static var appName: String { tr("app.name") }
    static var settings: String { tr("settings.title") }
    static var settingsEllipsis: String { tr("common.settings_ellipsis") }
    static var save: String { tr("common.save") }
    static var close: String { tr("common.close") }
    static var refresh: String { tr("common.refresh") }
    static var quit: String { tr("common.quit") }
    static var ok: String { tr("common.ok") }
    static var connected: String { tr("status.connected") }
    static var notConnected: String { tr("status.not_connected") }
    static var noStatus: String { tr("status.none") }
    static var noConnection: String { tr("status.no_connection") }

    static func remainingPercent(_ remaining: Double) -> String {
        tr("limit.remaining_pct", Int(remaining.rounded()))
    }

    static func resetLabel(relativeTo date: Date, now: Date = Date()) -> String {
        tr("limit.reset", relativeDateFormatter.localizedString(for: date, relativeTo: now))
    }

    static func connectedWithDetail(_ detail: String) -> String {
        if detail.isEmpty { return connected }
        if detail.localizedCaseInsensitiveContains(connected) { return detail }
        return "\(connected) · \(detail)"
    }
}

import Foundation

/// Pure threshold/cooldown policy for low-balance notifications.
enum LowBalanceNotifier {
    static let threshold = 15
    static let cooldown: TimeInterval = 12 * 60 * 60

    static func shouldNotify(lastNotified: Date?, now: Date) -> Bool {
        guard let lastNotified else { return true }
        return now.timeIntervalSince(lastNotified) >= cooldown
    }
}

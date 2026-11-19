import XCTest
@testable import CursorLimitsTray

final class LowBalanceNotifierTests: XCTestCase {
    func testFirstNotification() {
        XCTAssertTrue(LowBalanceNotifier.shouldNotify(lastNotified: nil, now: Date()))
    }

    func testCooldown() {
        let now = Date()
        XCTAssertFalse(
            LowBalanceNotifier.shouldNotify(
                lastNotified: now.addingTimeInterval(-60 * 60),
                now: now
            )
        )
        XCTAssertTrue(
            LowBalanceNotifier.shouldNotify(
                lastNotified: now.addingTimeInterval(-13 * 60 * 60),
                now: now
            )
        )
    }
}

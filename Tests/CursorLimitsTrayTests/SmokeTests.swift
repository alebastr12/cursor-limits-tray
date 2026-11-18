import XCTest
@testable import CursorLimitsTray

final class SmokeTests: XCTestCase {
    func testMenuBarTextGroupsProviders() {
        let segments = [
            MenuBarSegment(provider: .cursor, remainingPercent: 79, severity: .ok, kindLabel: "5h"),
            MenuBarSegment(provider: .cursor, remainingPercent: 56, severity: .low, kindLabel: "week"),
            MenuBarSegment(provider: .chatGPT, remainingPercent: 67, severity: .ok, kindLabel: "5h")
        ]
        XCTAssertEqual(MenuBarPresenter.plainText(segments: segments), "79% 56% · 67%")
    }
}

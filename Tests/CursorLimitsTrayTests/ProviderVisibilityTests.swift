import XCTest
@testable import CursorLimitsTray

final class ProviderVisibilityTests: XCTestCase {
    override func tearDown() {
        ProviderActivity.clearAll()
        super.tearDown()
    }

    func testStaleSecretWithoutDataIsHidden() {
        let empty = ProviderSnapshot(name: "Claude", status: "", rows: [], fetchedAt: nil, error: "HTTP 401")
        XCTAssertFalse(
            ProviderActivity.isVisible(id: .claude, connected: false, snapshot: empty),
            "A configured-but-never-working provider must not occupy the popover"
        )
    }

    func testStaleRowsKeepTheErrorVisible() {
        let stale = ProviderSnapshot(
            name: "ChatGPT",
            status: "",
            rows: [
                LimitRow(
                    id: "x",
                    title: "5h",
                    detail: "",
                    percentUsed: 42,
                    remainingLabel: nil,
                    resetLabel: nil
                )
            ],
            fetchedAt: Date(),
            error: "HTTP 401"
        )
        XCTAssertTrue(
            ProviderActivity.isVisible(id: .chatGPT, connected: false, snapshot: stale)
        )
    }

    func testPastSuccessKeepsSessionExpiredVisible() {
        ProviderActivity.markSuccess(.chatGPT)
        let empty = ProviderSnapshot(name: "ChatGPT", status: "", rows: [], fetchedAt: nil, error: "expired")
        XCTAssertTrue(
            ProviderActivity.isVisible(id: .chatGPT, connected: false, snapshot: empty)
        )
    }

    func testConnectedProviderIsVisible() {
        let empty = ProviderSnapshot(name: "Cursor", status: "", rows: [], fetchedAt: nil, error: nil)
        XCTAssertTrue(
            ProviderActivity.isVisible(id: .cursor, connected: true, snapshot: empty)
        )
    }

    func testPlaceholderRowWithoutPercentIsNotEnough() {
        let placeholder = ProviderSnapshot(
            name: "Claude",
            status: "",
            rows: [
                LimitRow(
                    id: "claude-empty",
                    title: "5h / week limits",
                    detail: "",
                    percentUsed: nil,
                    remainingLabel: nil,
                    resetLabel: nil
                )
            ],
            fetchedAt: Date(),
            error: nil
        )
        XCTAssertFalse(
            ProviderActivity.isVisible(id: .claude, connected: false, snapshot: placeholder)
        )
    }
}

import XCTest
@testable import CursorLimitsTray

final class ChatGPTParserTests: XCTestCase {
    func testPlusWindows() {
        let snapshot = ChatGPTUsageClient.mapUsage([
            "plan_type": "plus",
            "rate_limit": [
                "primary_window": [
                    "used_percent": 42,
                    "limit_window_seconds": 18_000,
                    "reset_after_seconds": 3_600
                ],
                "secondary_window": [
                    "used_percent": 12,
                    "limit_window_seconds": 604_800
                ]
            ],
            "credits": ["has_credits": false, "unlimited": false, "balance": "0"]
        ])

        XCTAssertEqual(snapshot.rows.count, 2)
        XCTAssertEqual(snapshot.rows[0].id, "cgpt-primary")
        XCTAssertEqual(snapshot.rows[0].title, L10n.tr("limit.window_5h"))
        XCTAssertEqual(snapshot.rows[0].percentUsed, 42)
        XCTAssertEqual(snapshot.rows[0].remainingLabel, L10n.remainingPercent(58))
        XCTAssertEqual(snapshot.rows[1].title, L10n.tr("limit.week"))
        XCTAssertEqual(snapshot.rows[1].percentUsed, 12)
        XCTAssertNil(snapshot.error)
    }

    func testTeamWeeklyPrimaryUsesDurationNotPosition() {
        let snapshot = ChatGPTUsageClient.mapUsage([
            "plan_type": "team",
            "rate_limit": [
                "primary_window": [
                    "used_percent": 54,
                    "limit_window_seconds": 604_800
                ],
                "secondary_window": NSNull()
            ]
        ])

        XCTAssertEqual(snapshot.rows.count, 1)
        XCTAssertEqual(snapshot.rows[0].title, L10n.tr("limit.week"))
        XCTAssertEqual(snapshot.rows[0].percentUsed, 54)
    }

    func testAdditionalRateLimitsKeepModelName() {
        let snapshot = ChatGPTUsageClient.mapUsage([
            "rate_limit": [
                "primary_window": ["used_percent": 10, "limit_window_seconds": 18_000],
                "additional_rate_limits": [[
                    "id": "codex-spark",
                    "title": "Codex Spark",
                    "primary_window": ["used_percent": 30, "limit_window_seconds": 18_000],
                    "secondary_window": ["used_percent": 70, "limit_window_seconds": 604_800]
                ]]
            ]
        ])

        XCTAssertEqual(snapshot.rows.count, 3)
        XCTAssertEqual(snapshot.rows[1].id, "cgpt-extra-codex-spark-primary")
        XCTAssertEqual(snapshot.rows[1].title, "Codex Spark · \(L10n.tr("limit.window_5h"))")
        XCTAssertEqual(snapshot.rows[2].title, "Codex Spark · \(L10n.tr("limit.week"))")
    }

    func testCreditsRowOnlyWhenPresent() {
        let withCredits = ChatGPTUsageClient.mapUsage([
            "credits": ["has_credits": true, "unlimited": false, "balance": "4.20"]
        ])
        XCTAssertEqual(withCredits.rows.last?.title, L10n.tr("limit.credits"))
        XCTAssertEqual(withCredits.rows.last?.remainingLabel, "4.20")

        let withoutCredits = ChatGPTUsageClient.mapUsage([
            "credits": ["has_credits": false, "unlimited": false, "balance": "0"]
        ])
        XCTAssertTrue(withoutCredits.rows.isEmpty)
    }

    func testLimitReachedIsVisibleInStatus() {
        let snapshot = ChatGPTUsageClient.mapUsage([
            "plan_type": "plus",
            "rate_limit": [
                "limit_reached": true,
                "primary_window": ["used_percent": 100, "limit_window_seconds": 18_000]
            ]
        ])
        XCTAssertTrue(snapshot.status.contains(L10n.tr("status.limit_reached")))
        XCTAssertEqual(snapshot.rows.first?.percentUsed, 100)
    }

    func testUsedPercentIsClamped() {
        let snapshot = ChatGPTUsageClient.mapUsage([
            "rate_limit": [
                "primary_window": ["used_percent": 130, "limit_window_seconds": 18_000]
            ]
        ])
        XCTAssertEqual(snapshot.rows.first?.percentUsed, 100)
        XCTAssertEqual(snapshot.rows.first?.remainingLabel, L10n.remainingPercent(0))
    }
}

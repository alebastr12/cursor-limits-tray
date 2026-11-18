import XCTest
@testable import CursorLimitsTray

final class CursorParserTests: XCTestCase {
    func testUsageSummaryPercent() {
        let snapshot = CursorUsageClient.mapUsageSummary([
            "membershipType": "pro",
            "individualUsage": [
                "plan": [
                    "totalPercentUsed": 79,
                    "used": 790,
                    "limit": 1000
                ]
            ]
        ])

        XCTAssertEqual(snapshot.rows.count, 1)
        XCTAssertEqual(snapshot.rows[0].title, L10n.tr("limit.plan_usage"))
        XCTAssertEqual(snapshot.rows[0].percentUsed, 79)
        XCTAssertNil(snapshot.error)
    }

    func testUsageSummaryFallsBackToCounts() {
        let snapshot = CursorUsageClient.mapUsageSummary([
            "individualUsage": [
                "plan": ["used": 250, "limit": 1000, "remaining": 750]
            ]
        ])

        XCTAssertEqual(snapshot.rows.count, 1)
        XCTAssertEqual(snapshot.rows[0].percentUsed, 25)
        XCTAssertEqual(snapshot.rows[0].detail, L10n.tr("limit.used_of", 250, 1000))
        XCTAssertEqual(snapshot.rows[0].remainingLabel, L10n.tr("limit.left_count", 750))
    }

    func testDashboardRows() {
        let snapshot = CursorUsageClient.mapDashboard(
            period: [
                "planUsage": [
                    "totalPercentUsed": 21,
                    "autoPercentUsed": 25,
                    "apiPercentUsed": 5
                ]
            ],
            sand: ["isUnified": true],
            plan: ["planInfo": ["planName": "Pro"]]
        )

        XCTAssertEqual(snapshot.rows.count, 3)
        XCTAssertEqual(snapshot.rows[0].title, L10n.tr("limit.weekly_pool"))
        XCTAssertEqual(snapshot.rows[1].title, L10n.tr("limit.cursor_models"))
        XCTAssertEqual(snapshot.rows[2].title, L10n.tr("limit.other_models"))
        XCTAssertTrue(snapshot.status.contains("Pro"))
        XCTAssertNil(snapshot.error)
    }

    func testEmptyDashboardHasLocalizedError() {
        let snapshot = CursorUsageClient.mapDashboard(period: [:], sand: [:], plan: [:])
        XCTAssertTrue(snapshot.rows.isEmpty)
        XCTAssertEqual(snapshot.error, L10n.tr("error.no_usage_fields"))
    }
}

import XCTest
@testable import CursorLimitsTray

final class OpenCodeGoParserTests: XCTestCase {
    func testAllWindows() {
        let snapshot = OpenCodeGoUsageClient.mapUsage([
            "rolling": [
                "percent": 16,
                "status": "ok",
                "resetsAt": "2026-11-19T22:49:10.000Z"
            ],
            "weekly": [
                "percent": 11,
                "status": "ok",
                "resetsAt": "2026-11-23T00:00:00.000Z"
            ],
            "monthly": [
                "percent": 5,
                "status": "ok",
                "resetsAt": "2026-12-18T18:27:34.000Z"
            ]
        ])

        XCTAssertEqual(snapshot.rows.count, 3)
        XCTAssertEqual(snapshot.rows.map(\.title), [
            L10n.tr("limit.window_5h"),
            L10n.tr("limit.week"),
            L10n.tr("limit.month")
        ])
        XCTAssertEqual(snapshot.rows.map(\.percentUsed), [16, 11, 5])
        XCTAssertEqual(snapshot.rows.first?.remainingLabel, L10n.remainingPercent(84))
        XCTAssertNotNil(snapshot.rows.first?.resetLabel)
        XCTAssertNil(snapshot.error)
    }

    func testMonthlyIsOptional() {
        let snapshot = OpenCodeGoUsageClient.mapUsage([
            "rolling": ["percent": 25],
            "weekly": ["percent": 50]
        ])
        XCTAssertEqual(snapshot.rows.count, 2)
        XCTAssertNil(snapshot.error)
    }

    func testPercentIsClamped() {
        let snapshot = OpenCodeGoUsageClient.mapUsage([
            "rolling": ["percent": 130],
            "weekly": ["percent": -5]
        ])
        XCTAssertEqual(snapshot.rows.map(\.percentUsed), [100, 0])
    }

    func testEmptyUsageHasError() {
        let snapshot = OpenCodeGoUsageClient.mapUsage([:])
        XCTAssertTrue(snapshot.rows.isEmpty)
        XCTAssertEqual(snapshot.error, L10n.tr("error.opencode_no_windows"))
    }
}

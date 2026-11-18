import XCTest
@testable import CursorLimitsTray

final class ClaudeParserTests: XCTestCase {
    func testLimitsArraySupersedesLegacyKeys() {
        let snapshot = ClaudeUsageClient.mapUsage([
            "five_hour": ["utilization": 90, "resets_at": "2026-11-18T20:00:00Z"],
            "limits": [
                [
                    "kind": "session",
                    "percent": 4,
                    "resets_at": "2026-11-18T20:00:00Z"
                ],
                [
                    "kind": "weekly_all",
                    "percent": 2
                ],
                [
                    "kind": "weekly_scoped",
                    "percent": 1,
                    "scope": ["model": ["display_name": "Fable"]]
                ]
            ]
        ], planLabel: "Pro")

        XCTAssertEqual(snapshot.rows.map(\.id), ["claude-lim-0", "claude-lim-1", "claude-lim-2"])
        XCTAssertEqual(snapshot.rows.map(\.title), [
            L10n.tr("limit.session"),
            L10n.tr("limit.week"),
            L10n.tr("limit.week_model")
        ])
        XCTAssertEqual(snapshot.rows.map(\.percentUsed), [4, 2, 1])
    }

    func testLegacyWindows() {
        let snapshot = ClaudeUsageClient.mapUsage([
            "five_hour": ["utilization": 40.0],
            "seven_day": ["utilization": 25.5]
        ], planLabel: "Max")

        XCTAssertEqual(snapshot.rows.count, 2)
        XCTAssertEqual(snapshot.rows[0].title, L10n.tr("limit.window_5h"))
        XCTAssertEqual(snapshot.rows[1].title, L10n.tr("limit.week"))
        XCTAssertEqual(snapshot.rows[0].percentUsed, 40)
    }

    func testEmptyResponseKeepsPlaceholderWithoutError() {
        let snapshot = ClaudeUsageClient.mapUsage([:], planLabel: "Free")
        XCTAssertEqual(snapshot.rows.count, 1)
        XCTAssertNil(snapshot.rows[0].percentUsed)
        XCTAssertNil(snapshot.error)
    }
}

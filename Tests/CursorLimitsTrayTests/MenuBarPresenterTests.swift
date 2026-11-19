import XCTest
@testable import CursorLimitsTray

final class MenuBarPresenterTests: XCTestCase {
    func testGroupsProvidersAndShowsAllLimits() {
        let snapshot = UsageSnapshot(
            cursor: ProviderSnapshot(
                name: "Cursor",
                status: "",
                rows: [
                    LimitRow(id: "c1", title: "5h", detail: "", percentUsed: 21, remainingLabel: nil, resetLabel: nil),
                    LimitRow(id: "c2", title: "week", detail: "", percentUsed: 44, remainingLabel: nil, resetLabel: nil)
                ],
                fetchedAt: nil,
                error: nil
            ),
            chatGPT: ProviderSnapshot(
                name: "ChatGPT",
                status: "",
                rows: [
                    LimitRow(id: "g1", title: "5h", detail: "", percentUsed: 33, remainingLabel: nil, resetLabel: nil)
                ],
                fetchedAt: nil,
                error: nil
            ),
            claude: .init(name: "Claude", status: "", rows: [], fetchedAt: nil, error: nil),
            openCodeGo: ProviderSnapshot(
                name: "OpenCode Go",
                status: "",
                rows: [
                    LimitRow(id: "o1", title: "5h", detail: "", percentUsed: 40, remainingLabel: nil, resetLabel: nil)
                ],
                fetchedAt: nil,
                error: nil
            ),
            isDemo: false
        )

        let output = MenuBarPresenter.make(
            snapshot: snapshot,
            cursorConnected: true,
            chatGPTConnected: true,
            claudeConnected: false,
            openCodeGoConnected: true
        )

        XCTAssertEqual(output.segments.map(\.remainingPercent), [79, 56, 67, 60])
        XCTAssertEqual(MenuBarPresenter.plainText(segments: output.segments), "79% 56% · 67% · 60%")
        XCTAssertEqual(output.cursorSeverity, .ok)
        XCTAssertEqual(output.chatGPTSeverity, .ok)
        XCTAssertEqual(output.claudeSeverity, .unknown)
        XCTAssertEqual(output.openCodeGoSeverity, .ok)
    }

    func testSeverityThresholds() {
        let snapshot = UsageSnapshot(
            cursor: .init(name: "Cursor", status: "", rows: [], fetchedAt: nil, error: nil),
            chatGPT: .init(name: "ChatGPT", status: "", rows: [], fetchedAt: nil, error: nil),
            claude: .init(name: "Claude", status: "", rows: [], fetchedAt: nil, error: nil),
            openCodeGo: .init(name: "OpenCode Go", status: "", rows: [], fetchedAt: nil, error: nil),
            isDemo: false
        )
        let low = UsageSnapshot(
            cursor: ProviderSnapshot(
                name: "Cursor",
                status: "",
                rows: [LimitRow(id: "x", title: "x", detail: "", percentUsed: 70, remainingLabel: nil, resetLabel: nil)],
                fetchedAt: nil,
                error: nil
            ),
            chatGPT: snapshot.chatGPT,
            claude: snapshot.claude,
            openCodeGo: snapshot.openCodeGo,
            isDemo: false
        )

        let output = MenuBarPresenter.make(
            snapshot: low,
            cursorConnected: true,
            chatGPTConnected: false,
            claudeConnected: false,
            openCodeGoConnected: false
        )
        XCTAssertEqual(output.cursorSeverity, .low)
        XCTAssertEqual(output.segments.first?.remainingPercent, 30)
    }

    func testDisconnectedProviderIsHidden() {
        let snapshot = UsageSnapshot.empty
        let output = MenuBarPresenter.make(
            snapshot: snapshot,
            cursorConnected: false,
            chatGPTConnected: true,
            claudeConnected: false,
            openCodeGoConnected: false
        )
        XCTAssertTrue(output.segments.isEmpty)
        XCTAssertEqual(MenuBarPresenter.tooltip(segments: []), L10n.tr("tooltip.empty"))
    }
}

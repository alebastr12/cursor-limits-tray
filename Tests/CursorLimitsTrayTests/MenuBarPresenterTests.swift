import XCTest
import AppKit
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

    func testAttributedTooltipHighlightsHeadersAndSeparatesProviders() {
        let segments = [
            MenuBarSegment(provider: .cursor, remainingPercent: 79, severity: .ok, kindLabel: "5h"),
            MenuBarSegment(provider: .chatGPT, remainingPercent: 67, severity: .ok, kindLabel: "5h")
        ]

        let attributed = MenuBarPresenter.tooltipAttributed(segments: segments)
        let text = attributed.string as NSString

        XCTAssertTrue(text.hasPrefix("Cursor\n"))
        XCTAssertTrue(text.contains("\n\nChatGPT\n"), "providers must be separated by a blank line")

        let headerRange = text.range(of: "Cursor")
        let lineRange = text.range(of: L10n.tr("tooltip.line", "5h", 79))
        XCTAssertNotEqual(headerRange.location, NSNotFound)
        XCTAssertNotEqual(lineRange.location, NSNotFound)

        let headerColor = attributed.attribute(
            .foregroundColor, at: headerRange.location, effectiveRange: nil
        ) as? NSColor
        let lineColor = attributed.attribute(
            .foregroundColor, at: lineRange.location, effectiveRange: nil
        ) as? NSColor
        XCTAssertNotNil(headerColor)
        XCTAssertNotNil(lineColor)
        XCTAssertNotEqual(headerColor, lineColor)
    }

    func testAttributedTooltipIncludesWarning() {
        let segments = [
            MenuBarSegment(provider: .cursor, remainingPercent: 79, severity: .ok, kindLabel: "5h")
        ]
        let attributed = MenuBarPresenter.tooltipAttributed(segments: segments, warning: "WARN")
        XCTAssertTrue(attributed.string.hasPrefix("WARN\n\nCursor\n"))
    }
}

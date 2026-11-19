import XCTest
@testable import CursorLimitsTray

final class AppVersionTests: XCTestCase {
    func testOrdering() {
        XCTAssertLessThan(AppVersion("0.2.31")!, AppVersion("0.2.32")!)
        XCTAssertLessThan(AppVersion("0.2")!, AppVersion("0.2.1")!)
        XCTAssertLessThan(AppVersion("0.9.9")!, AppVersion("1.0")!)
        XCTAssertEqual(AppVersion("v0.2.31"), AppVersion("0.2.31"))
        XCTAssertFalse(AppVersion("0.2.31")! < AppVersion("0.2.31")!)
    }

    func testPrereleaseSuffixIsIgnored() {
        XCTAssertEqual(AppVersion("0.2.31-beta")!, AppVersion("0.2.31")!)
    }

    func testInvalidVersions() {
        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("abc"))
        XCTAssertNil(AppVersion("1.x"))
    }
}

final class UpdateServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        HTTPClient.sessionOverride = URLSession(configuration: config)
        UpdateService.currentVersionOverride = "0.2.0"
    }

    override func tearDown() {
        HTTPClient.sessionOverride = nil
        UpdateService.currentVersionOverride = nil
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testLatestReleaseParsing() async throws {
        MockURLProtocol.handler = { _ in
            (200, self.json([
                "tag_name": "v0.2.99",
                "html_url": "https://github.com/example/releases/tag/v0.2.99",
                "body": "Release notes",
                "assets": [
                    [
                        "name": "TrayAILimits-0.2.99.zip",
                        "browser_download_url": "https://example.com/TrayAILimits-0.2.99.zip"
                    ],
                    [
                        "name": "TrayAILimits-0.2.99.dmg",
                        "browser_download_url": "https://example.com/TrayAILimits-0.2.99.dmg"
                    ],
                    [
                        "name": "SHA256SUMS-0.2.99.txt",
                        "browser_download_url": "https://example.com/SHA256SUMS-0.2.99.txt"
                    ]
                ]
            ]))
        }

        let release = try await UpdateService.latestRelease()
        XCTAssertEqual(release?.version, "0.2.99")
        XCTAssertEqual(release?.zipURL?.lastPathComponent, "TrayAILimits-0.2.99.zip")
        XCTAssertEqual(release?.checksumURL?.lastPathComponent, "SHA256SUMS-0.2.99.txt")
        XCTAssertEqual(release?.notes, "Release notes")
    }

    func testNoUpdateWhenCurrentIsNewer() async throws {
        UpdateService.currentVersionOverride = "9.0.0"
        MockURLProtocol.handler = { _ in
            (200, self.json(["tag_name": "v0.2.99", "assets": []]))
        }
        let release = try await UpdateService.latestRelease()
        XCTAssertNil(release)
    }

    func testChecksumParsing() {
        let sums = """
        aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  TrayAILimits-0.2.99.zip
        bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb  TrayAILimits-0.2.99.dmg
        """
        XCTAssertEqual(
            UpdateInstaller.parseChecksum(sums, assetName: "TrayAILimits-0.2.99.zip"),
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        )
        XCTAssertNil(UpdateInstaller.parseChecksum(sums, assetName: "missing.zip"))
    }

    private func json(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }
}

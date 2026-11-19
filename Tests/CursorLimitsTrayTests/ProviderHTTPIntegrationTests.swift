import XCTest
import SQLite3
@testable import CursorLimitsTray

final class ProviderHTTPIntegrationTests: XCTestCase {
    private var tempFiles: [URL] = []

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        HTTPClient.sessionOverride = URLSession(configuration: config)
    }

    override func tearDown() {
        HTTPClient.sessionOverride = nil
        OpenCodeLocalAuth.databasePathOverride = nil
        MockURLProtocol.handler = nil
        for url in tempFiles {
            try? FileManager.default.removeItem(at: url)
        }
        tempFiles.removeAll()
        super.tearDown()
    }

    func testOpenCodeGoSuccess() async throws {
        var usageRequest: URLRequest?
        MockURLProtocol.handler = { request in
            usageRequest = request
            return (200, self.json([
                "usage": [
                    "rolling": ["percent": 16, "status": "ok"],
                    "weekly": ["percent": 11, "status": "ok"],
                    "monthly": ["percent": 5, "status": "ok"]
                ]
            ]))
        }

        let snapshot = try await OpenCodeGoUsageClient.fetch(auth: .init(apiKey: "test-key"))
        XCTAssertEqual(snapshot.rows.map(\.percentUsed), [16, 11, 5])
        XCTAssertEqual(usageRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(usageRequest?.url?.path, "/zen/go/v1/usage")
    }

    func testOpenCodeGoUnauthorizedMapsToAuthError() async {
        MockURLProtocol.handler = { _ in
            (401, Data(#"{"error":"Unauthorized"}"#.utf8))
        }

        do {
            _ = try await OpenCodeGoUsageClient.fetch(auth: .init(apiKey: "bad-key"))
            XCTFail("Expected an auth failure")
        } catch let UsageError.auth(message) {
            XCTAssertFalse(message.isEmpty)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testClaudeWebWindows() async throws {
        MockURLProtocol.handler = { request in
            switch request.url?.path {
            case "/api/organizations":
                return (200, self.json([
                    ["uuid": "org-1", "plan_display_name": "Pro"]
                ]))
            case "/api/organizations/org-1/usage":
                return (200, self.json([
                    "five_hour": ["utilization": 40.0],
                    "seven_day": ["utilization": 25.0]
                ]))
            default:
                return (404, Data())
            }
        }

        let snapshot = try await ClaudeUsageClient.fetch(
            auth: .init(sessionCookie: "sessionKey=test")
        )
        XCTAssertEqual(snapshot.rows.count, 2)
        XCTAssertEqual(snapshot.rows.map(\.percentUsed), [40, 25])
        XCTAssertEqual(snapshot.rows.first?.title, L10n.tr("limit.window_5h"))
    }

    func testCursorUsageSummary() async throws {
        MockURLProtocol.handler = { request in
            guard request.url?.host == "cursor.com" else { return (404, Data()) }
            return (200, self.json([
                "membershipType": "pro",
                "individualUsage": [
                    "plan": ["totalPercentUsed": 79]
                ]
            ]))
        }

        let snapshot = try await CursorUsageClient.fetch(
            auth: .init(sessionCookie: "WorkosCursorSessionToken=test")
        )
        XCTAssertEqual(snapshot.rows.count, 1)
        XCTAssertEqual(snapshot.rows.first?.percentUsed, 79)
        XCTAssertEqual(snapshot.rows.first?.title, L10n.tr("limit.plan_usage"))
    }

    func testOpenCodeLocalAuthReadsCredential() throws {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("opencode-test-\(UUID().uuidString).db")
        tempFiles.append(dbURL)

        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        let sql = #"""
        CREATE TABLE credential (
            id text PRIMARY KEY,
            integration_id text,
            label text NOT NULL,
            value text NOT NULL,
            active integer,
            time_updated integer NOT NULL
        );
        INSERT INTO credential (id, integration_id, label, value, active, time_updated)
        VALUES ('c1', 'opencode', 'Personal', '{"access":"token-123","refresh":"r"}', 1, 1);
        """#
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)

        OpenCodeLocalAuth.databasePathOverride = dbURL.path
        let credentials = OpenCodeLocalAuth.load()
        XCTAssertEqual(credentials?.accessToken, "token-123")
        XCTAssertEqual(credentials?.source, "OpenCode CLI")
    }

    private func json(_ object: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }
}

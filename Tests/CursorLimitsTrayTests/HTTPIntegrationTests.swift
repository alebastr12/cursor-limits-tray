import XCTest
@testable import CursorLimitsTray

final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let (status, data) = handler(request)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://chatgpt.com")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class HTTPIntegrationTests: XCTestCase {
    private var codexDirectory: URL?

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        HTTPClient.sessionOverride = URLSession(configuration: config)
    }

    override func tearDown() {
        HTTPClient.sessionOverride = nil
        CodexLocalAuth.authFileOverride = nil
        MockURLProtocol.handler = nil
        if let codexDirectory {
            try? FileManager.default.removeItem(at: codexDirectory)
        }
        codexDirectory = nil
        super.tearDown()
    }

    func testWebSessionHappyPathSendsAccountAndCookie() async throws {
        let token = makeJWT()
        var usageRequest: URLRequest?

        MockURLProtocol.handler = { request in
            switch request.url?.path {
            case "/api/auth/session":
                return (200, self.json(["accessToken": token]))
            case "/backend-api/wham/usage":
                usageRequest = request
                return (200, self.json([
                    "plan_type": "plus",
                    "rate_limit": [
                        "primary_window": [
                            "used_percent": 42,
                            "limit_window_seconds": 18_000
                        ]
                    ]
                ]))
            default:
                return (404, Data())
            }
        }

        let snapshot = try await ChatGPTUsageClient.fetch(auth: .init(
            sessionCookie: "__Secure-next-auth.session-token=abc",
            bearerToken: nil,
            accountID: nil
        ))

        XCTAssertEqual(snapshot.rows.first?.percentUsed, 42)
        XCTAssertEqual(usageRequest?.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "acct_test")
        XCTAssertEqual(
            usageRequest?.value(forHTTPHeaderField: "Cookie"),
            "__Secure-next-auth.session-token=abc"
        )
    }

    func testRefreshAccessTokenErrorIsAuthExpired() async {
        MockURLProtocol.handler = { _ in
            (200, self.json([
                "error": "RefreshAccessTokenError",
                "accessToken": self.makeJWT(expiresIn: -3_600)
            ]))
        }

        do {
            _ = try await ChatGPTUsageClient.fetch(auth: .init(sessionCookie: "session=1"))
            XCTFail("Expected an auth failure")
        } catch let UsageError.authExpired(message) {
            XCTAssertFalse(message.isEmpty)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test401TokenExpiredIsAuthExpired() async {
        let token = makeJWT()
        MockURLProtocol.handler = { request in
            if request.url?.path == "/api/auth/session" {
                return (200, self.json(["accessToken": token]))
            }
            return (401, Data(#"{"code":"token_expired"}"#.utf8))
        }

        do {
            _ = try await ChatGPTUsageClient.fetch(auth: .init(sessionCookie: "session=1"))
            XCTFail("Expected an auth failure")
        } catch let UsageError.authExpired(message) {
            XCTAssertFalse(message.isEmpty)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testChatGPTFallsBackToCodexSession() async throws {
        let codexToken = makeJWT(accountID: "acct_codex")
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tray-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        codexDirectory = dir

        let authURL = dir.appendingPathComponent("auth.json")
        let authJSON: [String: Any] = [
            "tokens": [
                "access_token": codexToken,
                "account_id": "acct_codex"
            ]
        ]
        try JSONSerialization.data(withJSONObject: authJSON).write(to: authURL)
        CodexLocalAuth.authFileOverride = authURL

        MockURLProtocol.handler = { request in
            if request.url?.path == "/api/auth/session" {
                return (200, self.json([
                    "error": "RefreshAccessTokenError",
                    "accessToken": self.makeJWT(expiresIn: -3_600)
                ]))
            }
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer \(codexToken)" {
                return (200, self.json([
                    "plan_type": "plus",
                    "rate_limit": [
                        "secondary_window": [
                            "used_percent": 54,
                            "limit_window_seconds": 604_800
                        ]
                    ]
                ]))
            }
            return (401, Data(#"{"code":"token_expired"}"#.utf8))
        }

        let outcome = await ProviderFetcher.chatGPT(
            auth: .init(sessionCookie: "session=1"),
            allowWeb: true
        )

        XCTAssertTrue(outcome.webAttempted)
        XCTAssertTrue(outcome.webAuthFailed)
        XCTAssertEqual(outcome.provider.source, L10n.tr("source.codex_cli"))
        XCTAssertEqual(outcome.provider.snapshot?.rows.first?.percentUsed, 54)
        XCTAssertNil(outcome.provider.message)
    }

    // MARK: - Helpers

    private func makeJWT(
        expiresIn: TimeInterval = 3_600,
        accountID: String = "acct_test"
    ) -> String {
        let payload: [String: Any] = [
            "exp": Int(Date().timeIntervalSince1970 + expiresIn),
            "https://api.openai.com/auth": [
                "chatgpt_account_id": accountID
            ]
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "eyJhbGciOiJub25lIn0.\(encoded).signature"
    }

    private func json(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }
}

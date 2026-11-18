import XCTest
@testable import CursorLimitsTray

final class CookieHeaderTests: XCTestCase {
    func testKeepsSessionChunksAndWorkspaceCookie() {
        let header = ChatGPTCookieHeader.build(from: [
            (name: "__Secure-next-auth.session-token.1", value: "second"),
            (name: "__Secure-next-auth.session-token.0", value: "first"),
            (name: "_account", value: "acct"),
            (name: "oai-did", value: "device"),
            (name: "__cf_bm", value: "cloudflare"),
            (name: "g_state", value: "junk")
        ])

        XCTAssertEqual(
            header,
            "__Secure-next-auth.session-token.0=first; __Secure-next-auth.session-token.1=second; _account=acct; oai-did=device"
        )
        XCTAssertFalse(header?.contains("g_state") ?? true)
        XCTAssertFalse(header?.contains("__cf_bm") ?? true)
    }

    func testHeaderRequiresSessionCookie() {
        XCTAssertNil(ChatGPTCookieHeader.build(from: [
            (name: "_account", value: "acct")
        ]))
        XCTAssertNil(ChatGPTCookieHeader.build(from: [
            (name: "__Secure-next-auth.session-token", value: "")
        ]))
    }

    func testSingleSessionCookie() {
        XCTAssertEqual(
            ChatGPTCookieHeader.build(from: [
                (name: "__Secure-next-auth.session-token", value: "token")
            ]),
            "__Secure-next-auth.session-token=token"
        )
    }
}

final class JWTClaimsTests: XCTestCase {
    private func token(_ payload: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let base64 = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "eyJhbGciOiJub25lIn0.\(base64).signature"
    }

    func testExpiry() {
        let now = Int(Date().timeIntervalSince1970)
        XCTAssertTrue(JWTClaims.isExpired(token(["exp": now - 60])))
        XCTAssertTrue(JWTClaims.isExpired(token(["exp": now + 10])))
        XCTAssertFalse(JWTClaims.isExpired(token(["exp": now + 3_600])))
        // Opaque tokens must not be treated as expired.
        XCTAssertFalse(JWTClaims.isExpired("not-a-jwt"))
    }

    func testChatGPTAccountID() {
        let jwt = token([
            "https://api.openai.com/auth": [
                "chatgpt_account_id": "acct_123"
            ]
        ])
        XCTAssertEqual(JWTClaims.chatGPTAccountID(from: jwt), "acct_123")
        XCTAssertNil(JWTClaims.chatGPTAccountID(from: "not-a-jwt"))
    }
}

final class UsageErrorTests: XCTestCase {
    func testAuthFailures() {
        XCTAssertTrue(UsageError.authExpired("x").isAuthFailure)
        XCTAssertTrue(UsageError.auth("x").isAuthFailure)
        XCTAssertTrue(UsageError.notConfigured("x").isAuthFailure)
        XCTAssertTrue(UsageError.http(401, nil).isAuthFailure)
        XCTAssertTrue(UsageError.http(403, "token_expired").isAuthFailure)
        XCTAssertFalse(UsageError.http(500, "boom").isAuthFailure)
        XCTAssertFalse(UsageError.badResponse.isAuthFailure)
    }
}

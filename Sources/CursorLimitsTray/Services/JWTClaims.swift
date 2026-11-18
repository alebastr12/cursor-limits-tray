import Foundation

/// Minimal JWT payload reader — no signature validation (only used for local
/// expiry / account hints, never to trust a token).
enum JWTClaims {
    static func payload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }

    /// `false` for opaque (non-JWT) tokens — callers must not treat those as expired.
    static func isExpired(_ token: String, leeway: TimeInterval = 60) -> Bool {
        guard let payload = payload(token),
              let exp = payload["exp"] as? NSNumber
        else { return false }
        return Date(timeIntervalSince1970: exp.doubleValue) < Date().addingTimeInterval(leeway)
    }

    /// ChatGPT account id from the `https://api.openai.com/auth` claim.
    static func chatGPTAccountID(from token: String) -> String? {
        guard let payload = payload(token) else { return nil }
        guard let auth = payload["https://api.openai.com/auth"] as? [String: Any] else { return nil }
        for key in ["chatgpt_account_id", "chatgptAccountId"] {
            if let value = auth[key] as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }
}

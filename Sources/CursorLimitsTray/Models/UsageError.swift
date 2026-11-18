import Foundation

/// Shared provider errors. Lives in Models because every usage client uses it.
enum UsageError: LocalizedError, Equatable {
    case notConfigured(String)
    case auth(String)
    case authExpired(String)
    case http(Int, String?)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured(let message), .auth(let message), .authExpired(let message):
            return message
        case .http(let code, let body):
            let snippet = body.map { String($0.prefix(160)) } ?? ""
            return "HTTP \(code)\(snippet.isEmpty ? "" : ": \(snippet)")"
        case .badResponse:
            return L10n.tr("error.bad_response")
        }
    }

    /// The provider needs a new login, not a retry.
    var isAuthFailure: Bool {
        switch self {
        case .auth, .authExpired, .notConfigured: return true
        case .http(let code, let body):
            return code == 401 || (code == 403 && (body?.contains("token_expired") ?? false))
        case .badResponse: return false
        }
    }
}

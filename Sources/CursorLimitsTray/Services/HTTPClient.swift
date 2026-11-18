import Foundation

/// Shared HTTP entry point.
///
/// Every usage endpoint is polled repeatedly, so responses must never come from
/// URLCache: a manual "Refresh" has to hit the network. Timeouts also keep one
/// slow provider from blocking the whole refresh.
enum HTTPClient {
    static let noCache: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    /// Test seam: integration tests inject a `URLProtocol`-backed session.
    static var sessionOverride: URLSession?

    static func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var request = request
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let session = sessionOverride ?? noCache
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UsageError.badResponse }
        return (data, http)
    }

    static func json(
        for request: URLRequest,
        authExpiredBodyMarker: String? = nil
    ) async throws -> Any {
        let (data, http) = try await data(for: request)
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8)
            if let marker = authExpiredBodyMarker,
               http.statusCode == 401 || (http.statusCode == 403 && (body?.contains(marker) ?? false)) {
                throw UsageError.authExpired(L10n.tr("error.chatgpt_expired"))
            }
            throw UsageError.http(http.statusCode, body)
        }
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw UsageError.badResponse
        }
    }
}

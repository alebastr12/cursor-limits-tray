import Foundation

/// Thin named wrapper around the shared login window (see `WebLoginController`).
@MainActor
enum ClaudeConnectController {
    static let shared = WebLoginController(kind: .claude)
}

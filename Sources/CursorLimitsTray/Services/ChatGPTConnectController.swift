import Foundation

/// Thin named wrapper around the shared login window (see `WebLoginController`).
@MainActor
enum ChatGPTConnectController {
    static let shared = WebLoginController(kind: .chatGPT)
}

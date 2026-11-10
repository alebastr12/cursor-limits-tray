import Foundation

/// One live usage meter in the menu bar (icon shown once per contiguous provider group).
struct MenuBarSegment: Equatable {
    enum Provider: Equatable {
        case cursor
        case chatGPT
        case claude

        /// Template PNG in Resources/MenuBarProviders (not SF Symbol).
        var resourceName: String {
            switch self {
            case .cursor: return "ProviderCursor"
            case .chatGPT: return "ProviderChatGPT"
            case .claude: return "ProviderClaude"
            }
        }

        var accessibilityName: String {
            switch self {
            case .cursor: return "Cursor"
            case .chatGPT: return "ChatGPT"
            case .claude: return "Claude"
            }
        }
    }

    let provider: Provider
    let remainingPercent: Int
    let severity: LimitSeverity
}

import Foundation

/// One connected provider in the menu bar: icon + remaining %.
struct MenuBarSegment: Equatable {
    enum Provider: Equatable {
        case cursor
        case chatGPT
        case claude

        /// Generic SF Symbols — not vendor logos.
        var symbolName: String {
            switch self {
            case .cursor: return "chevron.left.forwardslash.chevron.right"
            case .chatGPT: return "bubble.left.fill"
            case .claude: return "sparkles"
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

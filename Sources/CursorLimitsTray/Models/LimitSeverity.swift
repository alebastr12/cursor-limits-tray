import SwiftUI

enum LimitSeverity: Equatable {
    case ok, low, critical, unknown

    var color: Color {
        switch self {
        case .ok: return Color(red: 0.20, green: 0.75, blue: 0.40)
        case .low: return Color(red: 0.95, green: 0.70, blue: 0.15)
        case .critical: return Color(red: 0.95, green: 0.30, blue: 0.28)
        case .unknown: return Color.secondary
        }
    }
}

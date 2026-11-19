import Foundation

/// One source of truth for the popover/panel size.
enum PopoverLayout {
    static let width: CGFloat = 360

    static func height(forVisibleProviders count: Int) -> CGFloat {
        switch count {
        case 0: return 280
        case 1: return 360
        case 2: return 480
        case 3: return 560
        default: return 640
        }
    }
}

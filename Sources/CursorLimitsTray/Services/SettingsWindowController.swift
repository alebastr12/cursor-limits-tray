import AppKit
import SwiftUI

/// Own Settings window (not a sheet on the tray panel), so confirmation alerts
/// inside it cannot be covered by the popover panel.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show(poller: UsagePoller) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: SettingsView(poller: poller))
        let window = NSWindow(contentViewController: hosting)
        window.title = L10n.settings
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 500, height: 720))
        window.minSize = NSSize(width: 500, height: 720)
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        TrayLifecycle.returnToTrayOnlyIfNoUserWindows()
    }
}

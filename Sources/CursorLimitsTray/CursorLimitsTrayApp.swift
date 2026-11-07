import SwiftUI
import AppKit

@main
struct CursorLimitsTrayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Status item + popover are owned by StatusItemController (AppKit).
        // Closing this window must NOT quit — see AppDelegate.

        Window("Лимиты", id: "debug-popover") {
            PopoverView(poller: appDelegate.poller)
                .onAppear { appDelegate.poller.start() }
        }
        .defaultSize(width: 360, height: 560)
        .windowResizability(.contentSize)
        .commandsRemoved()

        Settings {
            SettingsView(poller: appDelegate.poller)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let poller = UsagePoller()
    private var windowCloseObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = ProcessInfo.processInfo.arguments
        let snapshotIdx = args.firstIndex(of: "--snapshot")
        let snapshotPath = snapshotIdx.flatMap { idx -> String? in
            args.indices.contains(idx + 1) ? args[idx + 1] : nil
        }
        let settingsIdx = args.firstIndex(of: "--snapshot-settings")
        let settingsPath = settingsIdx.flatMap { idx -> String? in
            args.indices.contains(idx + 1) ? args[idx + 1] : nil
        }
        let wantsWindow = args.contains("--window") || snapshotPath != nil || settingsPath != nil

        if wantsWindow {
            TrayLifecycle.beginShowingWindow()
            NSApp.activate(ignoringOtherApps: true)
        } else {
            TrayLifecycle.returnToTrayOnly()
        }

        // Install live menu-bar item unless we're only doing offline snapshot export.
        if snapshotPath == nil && settingsPath == nil {
            StatusItemController.shared.install(poller: poller)
            // Default ON: register login item; prompt once if launched from a DMG.
            LoginItemBootstrap.applyOnLaunch()
        }

        windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { _ in
            // After the closing window finishes tearing down, drop back to tray-only if nothing left.
            DispatchQueue.main.async {
                TrayLifecycle.returnToTrayOnlyIfNoUserWindows()
            }
        }

        if snapshotPath != nil || settingsPath != nil {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)
                if let snapshotPath {
                    if args.contains("--demo") {
                        SnapshotExporter.writeDemoMain(to: snapshotPath)
                    } else {
                        await SnapshotExporter.writeLiveMain(to: snapshotPath)
                    }
                }
                if let settingsPath {
                    let p = UsagePoller()
                    _ = SessionSecrets.cursorAuth()
                    _ = await p.autoConnectChatGPTIfNeeded()
                    _ = await p.autoConnectClaudeIfNeeded()
                    await p.refresh()
                    SnapshotExporter.writeSettings(
                        to: settingsPath,
                        cursorOK: p.cursorConnected || !(p.snapshot.cursor.rows.isEmpty),
                        chatOK: p.chatGPTConnected || !(p.snapshot.chatGPT.rows.isEmpty),
                        claudeOK: p.claudeConnected || !(p.snapshot.claude.rows.isEmpty)
                    )
                }
                NSApp.terminate(nil)
            }
            return
        }

        if args.contains("--window") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                NotificationCenter.default.post(name: .limitsTrayOpenDebugWindow, object: nil)
            }
        }

        if args.contains("--connect-chatgpt") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                TrayLifecycle.beginShowingWindow()
                NSApp.activate(ignoringOtherApps: true)
                ChatGPTConnectController.shared.present { header in
                    self.poller.saveChatGPTCookie(header)
                }
            }
        }

        if args.contains("--connect-claude") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                TrayLifecycle.beginShowingWindow()
                NSApp.activate(ignoringOtherApps: true)
                ClaudeConnectController.shared.present { header in
                    self.poller.saveClaudeCookie(header)
                }
            }
        }
    }

    /// Red traffic-light / Cmd+W / last window closed → stay in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Dock reopen is irrelevant for LSUIElement; never force-quit logic via "no windows".
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // Keep tray; optional: could re-open debug window — we don't.
        }
        return false
    }

    deinit {
        if let windowCloseObserver {
            NotificationCenter.default.removeObserver(windowCloseObserver)
        }
    }
}

/// Activation policy helpers: floating login / debug window use `.regular`, then back to `.accessory` (tray-only).
enum TrayLifecycle {
    static func beginShowingWindow() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
    }

    static func returnToTrayOnly() {
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Hide Dock icon again when no user-facing windows remain (status item is not an NSWindow).
    static func returnToTrayOnlyIfNoUserWindows() {
        let remaining = NSApp.windows.filter { window in
            guard window.isVisible else { return false }
            // Ignore borderless snapshot / hosting helpers if any linger.
            if window.styleMask.contains(.borderless) && window.title.isEmpty { return false }
            return true
        }
        if remaining.isEmpty {
            returnToTrayOnly()
        }
    }
}

extension Notification.Name {
    static let limitsTrayShouldStart = Notification.Name("limitsTrayShouldStart")
    static let limitsTrayOpenDebugWindow = Notification.Name("limitsTrayOpenDebugWindow")
}

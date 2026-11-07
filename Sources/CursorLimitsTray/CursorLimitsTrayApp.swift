import SwiftUI
import AppKit

@main
struct CursorLimitsTrayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Status item + popover are owned by StatusItemController (AppKit),
        // so the live title near the notch updates reliably with colors.

        Window("Лимиты", id: "debug-popover") {
            PopoverView(poller: appDelegate.poller)
                .onAppear { appDelegate.poller.start() }
        }
        .defaultSize(width: 360, height: 480)
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
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }

        // Install live menu-bar item unless we're only doing offline snapshot export.
        if snapshotPath == nil && settingsPath == nil {
            StatusItemController.shared.install(poller: poller)
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
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                ChatGPTConnectController.shared.present { header in
                    self.poller.saveChatGPTCookie(header)
                }
            }
        }

        if args.contains("--connect-claude") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                ClaudeConnectController.shared.present { header in
                    self.poller.saveClaudeCookie(header)
                }
            }
        }
    }
}

extension Notification.Name {
    static let limitsTrayShouldStart = Notification.Name("limitsTrayShouldStart")
    static let limitsTrayOpenDebugWindow = Notification.Name("limitsTrayOpenDebugWindow")
}

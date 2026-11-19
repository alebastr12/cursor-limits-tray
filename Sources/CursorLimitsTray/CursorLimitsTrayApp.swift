import SwiftUI
import AppKit

@main
struct CursorLimitsTrayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Status item + popover are owned by StatusItemController (AppKit).
        // Closing this window must NOT quit — see AppDelegate.

        // Debug-only window (opened via notification / --window). Kept out of normal tray use
        // so it does not steal Space/window identity from the fullscreen-capable status panel.
        Window("TrayAILimitsDebug", id: "debug-popover") {
            PopoverView(poller: appDelegate.poller)
                .onAppear { appDelegate.poller.start() }
        }
        .defaultSize(width: 360, height: 560)
        .windowResizability(.contentSize)
        .commandsRemoved()

    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let poller = UsagePoller()
    private var windowCloseObserver: NSObjectProtocol?
    private var showPanelObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationService.shared.configure()

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

        if !wantsWindow {
            // The debug Window scene is only for probes; do not leave it on screen
            // during normal tray use.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                NSApp.windows
                    .filter { $0.title == "TrayAILimitsDebug" }
                    .forEach { $0.orderOut(nil) }
            }
        }

        let printTooltipOnly = args.contains("--print-tooltip")
        let probeChatGPT = args.contains("--probe-chatgpt")

        // Install live menu-bar item unless we're only doing offline snapshot / tooltip probe.
        if snapshotPath == nil && settingsPath == nil && !printTooltipOnly && !probeChatGPT {
            StatusItemController.shared.install(poller: poller)
            // Default ON: register login item; prompt once if launched from a DMG.
            LoginItemBootstrap.applyOnLaunch()
            showPanelObserver = DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("local.cursor-limits-tray.showPanel"),
                object: nil,
                queue: .main
            ) { _ in
                StatusItemController.shared.showPanelForProbe()
            }
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

        if args.contains("--probe-keychain") {
            Task { @MainActor in
                var lines: [String] = []
                lines.append("keychainUnlocked: \(KeychainLock.isUnlocked)")
                let file = FileSecretStore.all()
                let fileSummary = file.isEmpty
                    ? "empty"
                    : file.map { "\($0.key)(len=\($0.value.count))" }.sorted().joined(separator: ", ")
                lines.append("file: \(fileSummary)")
                for account in KeychainStore.Account.allCases {
                    lines.append("\(account.rawValue): presence=\(SecretsPresence.has(account))")
                }
                fputs(lines.joined(separator: "\n") + "\n", stdout)
                fflush(stdout)
                NSApp.terminate(nil)
            }
            return
        }

        if args.contains("--probe-chatgpt") {
            Task { @MainActor in
                var lines: [String] = []
                var cookie = SessionSecrets.get(.chatGPTSessionCookie)
                if cookie == nil, KeychainLock.isUnlocked {
                    cookie = await WebKitCookieBridge.chatGPTSessionCookie()
                }

                if let cookie {
                    do {
                        let snap = try await ChatGPTUsageClient.fetch(auth: .init(
                            sessionCookie: cookie,
                            bearerToken: SessionSecrets.get(.chatGPTBearerOverride),
                            accountID: nil
                        ))
                        lines.append(Self.probeLine("app-session", snap))
                    } catch {
                        lines.append("app-session: \(error.localizedDescription)")
                    }
                } else {
                    lines.append("app-session: no cookie in Keychain or WebKit store")
                }

                if let codex = CodexLocalAuth.load() {
                    do {
                        let snap = try await ChatGPTUsageClient.fetch(auth: .init(
                            sessionCookie: nil,
                            bearerToken: codex.accessToken,
                            accountID: codex.accountID
                        ))
                        lines.append(Self.probeLine("codex-cli", snap))
                    } catch {
                        lines.append("codex-cli: \(error.localizedDescription)")
                    }
                } else {
                    lines.append("codex-cli: no usable \(CodexLocalAuth.authFileURL().path)")
                }

                fputs(lines.joined(separator: "\n") + "\n", stdout)
                fflush(stdout)
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

        if args.contains("--show-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                StatusItemController.shared.showPanelForProbe()
            }
        }

        if args.contains("--open-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                TrayLifecycle.beginShowingWindow()
                SettingsWindowController.shared.show(poller: self.poller)
            }
        }

        if args.contains("--print-tooltip") {
            // Sync probe for CI / local verify (demo is instant; live waits on refresh Task below).
            if args.contains("--demo") {
                poller.applyDemoSnapshot()
                fputs(MenuBarPresenter.tooltip(segments: poller.menuBarSegments) + "\n", stdout)
                fflush(stdout)
                NSApp.terminate(nil)
                return
            }
            Task { @MainActor in
                _ = SessionSecrets.cursorAuth()
                await poller.refresh()
                if let warning = poller.providerWarning {
                    fputs(L10n.tr("tooltip.warning", warning) + "\n", stdout)
                }
                fputs(MenuBarPresenter.tooltip(segments: poller.menuBarSegments) + "\n", stdout)
                fflush(stdout)
                NSApp.terminate(nil)
            }
            return
        }
    }

    /// Redacted probe output — titles and percentages only, never tokens/cookies.
    private static func probeLine(_ source: String, _ snap: ProviderSnapshot) -> String {
        let rows = snap.rows.map { row -> String in
            let used = row.percentUsed.map { String(format: "%.0f%%", $0) } ?? "—"
            return "\(row.title)=\(used)"
        }.joined(separator: ", ")
        return "\(source): ok status=\(snap.status) rows=[\(rows)]"
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

/// Activation policy helpers: login / Settings use `.regular`, then back to `.accessory` (tray-only).
///
/// Critical: never flip to `.accessory` while Settings (or another user window) is still open —
/// that freezes SwiftUI buttons after Claude/ChatGPT login panels close.
enum TrayLifecycle {
    /// Nested present() of connect panels / alerts that need `.regular`.
    private static var sessionDepth = 0

    static func beginShowingWindow() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
    }

    static func beginSessionWindow() {
        sessionDepth += 1
        beginShowingWindow()
    }

    static func endSessionWindow() {
        sessionDepth = max(0, sessionDepth - 1)
        // Let the closing window finish resigning key, then restore Settings focus.
        DispatchQueue.main.async {
            restoreKeyToBestUserWindow()
            DispatchQueue.main.async {
                returnToTrayOnlyIfNoUserWindows()
            }
        }
    }

    static func returnToTrayOnly() {
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    static func isLoginWindow(_ window: NSWindow) -> Bool {
        let t = window.title
        return t == L10n.tr("connect.chatgpt.title")
            || t == L10n.tr("connect.claude.title")
            || t.localizedCaseInsensitiveContains("Connect")
            || t.contains("Подключение") // legacy / fallback
    }

    static func isSettingsLikeWindow(_ window: NSWindow) -> Bool {
        let t = window.title
        return t == L10n.settings
            || t.localizedCaseInsensitiveContains("Settings")
            || t.localizedCaseInsensitiveContains("Preferences")
            || t.contains("Настройки") // legacy / fallback
    }

    /// Visible windows that should keep the app in `.regular` (Settings, debug, login).
    static func userFacingWindows(includingLogin: Bool = true) -> [NSWindow] {
        NSApp.windows.filter { window in
            guard window.isVisible else { return false }
            if window.styleMask.contains(.borderless) && window.title.isEmpty { return false }
            if !includingLogin && isLoginWindow(window) { return false }
            return true
        }
    }

    static func restoreKeyToBestUserWindow() {
        let windows = userFacingWindows(includingLogin: false)
        let preferred = windows.first(where: isSettingsLikeWindow) ?? windows.first
        guard let preferred else { return }
        beginShowingWindow()
        preferred.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Hide Dock icon again when no user-facing windows remain (status item is not an NSWindow).
    static func returnToTrayOnlyIfNoUserWindows() {
        let remaining = userFacingWindows(includingLogin: true)
        if remaining.isEmpty && sessionDepth == 0 {
            returnToTrayOnly()
        } else {
            // Settings (or login) still up — stay interactive.
            beginShowingWindow()
            if NSApp.keyWindow == nil || (NSApp.keyWindow.map(isLoginWindow) == true) {
                restoreKeyToBestUserWindow()
            }
        }
    }
}

extension Notification.Name {
    static let limitsTrayShouldStart = Notification.Name("limitsTrayShouldStart")
    static let limitsTrayOpenDebugWindow = Notification.Name("limitsTrayOpenDebugWindow")
}

import AppKit
import ServiceManagement
import Foundation

/// Default «Открывать при входе» ON; respects explicit user off. DMG → optional copy (no admin loop).
enum LoginItemBootstrap {
    private static let prefersKey = "loginItem.prefersOpenAtLogin"
    private static let dmgPromptKey = "install.dmgCopyPromptDone"
    private static var didApplyThisProcess = false

    static var prefersOpenAtLogin: Bool {
        get {
            if UserDefaults.standard.object(forKey: prefersKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: prefersKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: prefersKey) }
    }

    static func applyOnLaunch() {
        guard !didApplyThisProcess else { return }
        didApplyThisProcess = true
        offerCopyFromDMGIfNeeded()
        // Never block launch with login-item auth. Best-effort, errors swallowed.
        syncLoginItemWithPreference(quiet: true)
    }

    static func syncLoginItemWithPreference(quiet: Bool = false) {
        // Running from a disk image — skip register (often fails / prompts); user copies to Apps first.
        if Bundle.main.bundlePath.hasPrefix("/Volumes/") { return }
        do {
            if prefersOpenAtLogin {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            fputs("LoginItemBootstrap: \(error.localizedDescription)\n", stderr)
            if !quiet {
                // Caller (Settings save) surfaces the error.
            }
        }
    }

    private static func offerCopyFromDMGIfNeeded() {
        let path = Bundle.main.bundlePath
        guard path.hasPrefix("/Volumes/") else { return }
        guard !UserDefaults.standard.bool(forKey: dmgPromptKey) else { return }
        UserDefaults.standard.set(true, forKey: dmgPromptKey)

        let alert = NSAlert()
        alert.messageText = L10n.tr("install.copy_title")
        alert.informativeText = L10n.tr("install.copy_body")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.tr("install.copy_button"))
        alert.addButton(withTitle: L10n.tr("common.not_now"))

        TrayLifecycle.beginShowingWindow()
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        TrayLifecycle.returnToTrayOnlyIfNoUserWindows()

        guard response == .alertFirstButtonReturn else { return }
        copyToApplicationsAndRelaunch(from: path)
    }

    private static func copyToApplicationsAndRelaunch(from bundlePath: String) {
        // Replacing a running copy can make Finder ask for an administrator
        // password. Quit old instances first, then install without elevation.
        quitOtherInstances()

        if let destination = install(from: bundlePath) {
            NSWorkspace.shared.open(destination)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                NSApp.terminate(nil)
            }
            return
        }

        let alert = NSAlert()
        alert.messageText = L10n.tr("install.copy_fail_title")
        alert.informativeText = L10n.tr(
            "install.copy_fail_body",
            lastInstallError?.localizedDescription ?? ""
        )
        alert.runModal()
    }

    private static var lastInstallError: Error?

    /// Prefer `/Applications`; fall back to `~/Applications` when the system
    /// location is not writable (or contains a copy owned by someone else).
    /// Neither path needs an administrator password.
    private static func install(from bundlePath: String) -> URL? {
        let fm = FileManager.default
        let homeApplications = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        let destinations = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            homeApplications
        ]

        lastInstallError = nil
        for directory in destinations {
            let destination = directory.appendingPathComponent("TrayAILimits.app", isDirectory: true)
            do {
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
                if fm.fileExists(atPath: destination.path) {
                    try fm.removeItem(at: destination)
                }
                try fm.copyItem(atPath: bundlePath, toPath: destination.path)
                return destination
            } catch {
                lastInstallError = error
                // Clean up a partial copy before trying the next location.
                try? fm.removeItem(at: destination)
            }
        }
        return nil
    }

    private static func quitOtherInstances() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != currentPID }
        guard !others.isEmpty else { return }

        others.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline, others.contains(where: { !$0.isTerminated }) {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        others.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
    }
}

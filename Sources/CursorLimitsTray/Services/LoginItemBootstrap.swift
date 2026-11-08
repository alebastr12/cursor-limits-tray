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
        let fm = FileManager.default
        let dest = "/Applications/TrayAILimits.app"
        do {
            if fm.fileExists(atPath: dest) {
                // Prefer replace without elevating; if locked, show manual drag (no auth retry).
                try fm.removeItem(atPath: dest)
            }
            try fm.copyItem(atPath: bundlePath, toPath: dest)
            NSWorkspace.shared.open(URL(fileURLWithPath: dest))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                NSApp.terminate(nil)
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = L10n.tr("install.copy_fail_title")
            alert.informativeText = L10n.tr("install.copy_fail_body", error.localizedDescription)
            alert.runModal()
        }
    }
}

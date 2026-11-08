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
        syncLoginItemWithPreference()
    }

    static func syncLoginItemWithPreference() {
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
        }
    }

    private static func offerCopyFromDMGIfNeeded() {
        let path = Bundle.main.bundlePath
        guard path.hasPrefix("/Volumes/") else { return }
        guard !UserDefaults.standard.bool(forKey: dmgPromptKey) else { return }
        UserDefaults.standard.set(true, forKey: dmgPromptKey)

        let alert = NSAlert()
        alert.messageText = "Установить в Программы?"
        alert.informativeText = "Запуск с DMG. Скопируйте в «Программы» — так надёжнее работает «Открывать при входе» (без пароля администратора при обычной установке)."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Скопировать в Программы")
        alert.addButton(withTitle: "Не сейчас")

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
            alert.messageText = "Не удалось скопировать без пароля"
            alert.informativeText = "Перетащите TrayAILimits.app в «Программы» вручную.\n\(error.localizedDescription)"
            alert.runModal()
        }
    }
}

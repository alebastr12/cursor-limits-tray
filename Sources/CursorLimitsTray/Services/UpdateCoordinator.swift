import Foundation
import Combine
import AppKit

/// Checks GitHub Releases daily and optionally installs the update.
@MainActor
final class UpdateCoordinator: ObservableObject {
    static let shared = UpdateCoordinator()

    @Published private(set) var status: String?
    @Published private(set) var isChecking = false
    @Published private(set) var isInstalling = false

    private var timer: Timer?
    private var didStart = false

    func start() {
        guard !didStart else { return }
        guard !AppPreferences.forceDemoMode,
              !ProcessInfo.processInfo.arguments.contains("--demo")
        else { return }
        didStart = true

        timer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check(manual: false) }
        }

        guard AppPreferences.autoUpdateEnabled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            Task { @MainActor in await self?.check(manual: false) }
        }
    }

    func check(manual: Bool) async {
        guard !isChecking, !isInstalling else { return }
        if !manual, !AppPreferences.autoUpdateEnabled { return }
        if !manual, AppPreferences.forceDemoMode || ProcessInfo.processInfo.arguments.contains("--demo") {
            return
        }
        if !manual, let last = AppPreferences.lastUpdateCheck,
           Date().timeIntervalSince(last) < 24 * 60 * 60 {
            return
        }

        isChecking = true
        status = L10n.tr("update.checking")
        AppPreferences.lastUpdateCheck = Date()
        defer { isChecking = false }

        do {
            guard let release = try await UpdateService.latestRelease() else {
                status = L10n.tr("update.latest")
                return
            }
            status = L10n.tr("update.available", release.version)

            if manual {
                promptToInstall(release)
            } else {
                await install(release, manual: false)
            }
        } catch {
            status = L10n.tr("update.failed", error.localizedDescription)
            if manual { showError(error) }
        }
    }

    private func promptToInstall(_ release: UpdateRelease) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L10n.tr("update.available_title", release.version)
        alert.informativeText = String(release.notes.prefix(600))
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.tr("update.install"))
        alert.addButton(withTitle: L10n.tr("common.not_now"))
        alert.window.level = .floating

        if alert.runModal() == .alertFirstButtonReturn {
            Task { @MainActor in
                await install(release, manual: true)
            }
        }
    }

    private func install(_ release: UpdateRelease, manual: Bool) async {
        guard !isInstalling else { return }
        isInstalling = true
        status = L10n.tr("update.installing", release.version)

        do {
            try await UpdateInstaller.install(release)
            status = L10n.tr("update.installed", release.version)
            NotificationService.shared.notifyUpdateInstalled(version: release.version)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                NSApp.terminate(nil)
            }
        } catch {
            isInstalling = false
            status = L10n.tr("update.failed", error.localizedDescription)
            if manual { showError(error) }
        }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = L10n.tr("update.failed_title")
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.close)
        alert.runModal()
    }
}

import AppKit
import SwiftUI
import Combine

/// AppKit status item with compact brand-icon + % title near the notch.
@MainActor
final class StatusItemController: NSObject {
    static let shared = StatusItemController()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var poller: UsagePoller?
    private var cancellables = Set<AnyCancellable>()
    private var eventMonitor: Any?

    func install(poller: UsagePoller) {
        self.poller = poller

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover(_:))
        item.button?.imagePosition = .imageOnly
        item.button?.setAccessibilityTitle(L10n.appName)
        statusItem = item

        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = true
        pop.contentSize = NSSize(width: 360, height: 280)
        pop.contentViewController = NSHostingController(rootView: PopoverView(poller: poller))
        popover = pop

        poller.$menuBarSegments
            .combineLatest(poller.$cursorConnected, poller.$chatGPTConnected, poller.$claudeConnected)
            .receive(on: RunLoop.main)
            .sink { [weak self] segments, cOK, gOK, aOK in
                guard let self else { return }
                self.applyTitle(segments: segments)
                let n = [cOK, gOK, aOK].filter { $0 }.count
                let height: CGFloat
                switch n {
                case 0: height = 280
                case 1: height = 360
                case 2: height = 480
                default: height = 560
                }
                self.popover?.contentSize = NSSize(width: 360, height: height)
            }
            .store(in: &cancellables)

        applyTitle(segments: poller.menuBarSegments)
        poller.start()
    }

    private func applyTitle(segments: [MenuBarSegment]) {
        guard let button = statusItem?.button else { return }

        let a11y = segments.isEmpty
            ? L10n.tr("a11y.menubar_empty")
            : L10n.appName + " " + segments.map {
                L10n.tr("a11y.menubar_item", $0.provider.accessibilityName, $0.remainingPercent)
            }.joined(separator: ", ")
        button.setAccessibilityTitle(a11y)

        if segments.isEmpty {
            button.attributedTitle = NSAttributedString(string: "")
            button.image = appGlyph()
            button.imagePosition = .imageOnly
            return
        }

        button.image = nil
        button.imagePosition = .noImage
        button.attributedTitle = composedTitle(segments: segments)
    }

    private func composedTitle(segments: [MenuBarSegment]) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        let result = NSMutableAttributedString()
        let providerSeparator = NSAttributedString(
            string: " · ",
            attributes: [
                .font: font,
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        let sameProviderGap = NSAttributedString(
            string: " ",
            attributes: [.font: font]
        )

        for (index, segment) in segments.enumerated() {
            let previous = index > 0 ? segments[index - 1] : nil
            let isNewProvider = previous.map { $0.provider != segment.provider } ?? true

            if index > 0 {
                result.append(isNewProvider ? providerSeparator : sameProviderGap)
            }

            let color = nsColor(segment.severity)
            // One brand icon per provider; extra limits for the same provider are bare %.
            if isNewProvider,
               let icon = providerAttachment(resource: segment.provider.resourceName, color: color, font: font) {
                result.append(NSAttributedString(attachment: icon))
                result.append(NSAttributedString(
                    string: "\u{200A}",
                    attributes: [.font: font]
                ))
            }

            result.append(NSAttributedString(
                string: "\(segment.remainingPercent)%",
                attributes: [
                    .font: font,
                    .foregroundColor: color
                ]
            ))
        }
        return result
    }

    private func providerAttachment(resource: String, color: NSColor, font: NSFont) -> NSTextAttachment? {
        guard let base = loadProviderTemplate(named: resource) else { return nil }
        // ~14–16pt: readable next to %, still fits menu-bar / notch.
        let side: CGFloat = 15
        let size = NSSize(width: side, height: side)
        let tinted = NSImage(size: size, flipped: false) { rect in
            // Template: draw as mask then fill with severity color.
            base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        let attachment = NSTextAttachment()
        attachment.image = tinted
        let yOffset = (font.capHeight - side) / 2
        attachment.bounds = CGRect(x: 0, y: yOffset, width: side, height: side)
        return attachment
    }

    private func loadProviderTemplate(named: String) -> NSImage? {
        if let url = Bundle.main.url(forResource: named, withExtension: "png", subdirectory: "MenuBarProviders"),
           let img = NSImage(contentsOf: url) {
            img.isTemplate = true
            return img
        }
        if let url = Bundle.main.url(forResource: named, withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            img.isTemplate = true
            return img
        }
        // Fallback path when resources are copied flat into Resources/
        let path = Bundle.main.bundlePath + "/Contents/Resources/MenuBarProviders/\(named).png"
        if let img = NSImage(contentsOfFile: path) {
            img.isTemplate = true
            return img
        }
        return nil
    }

    private func appGlyph() -> NSImage? {
        if let url = Bundle.main.url(forResource: "MenuBarGlyph", withExtension: "png"),
           let custom = NSImage(contentsOf: url) {
            custom.isTemplate = true
            custom.size = NSSize(width: 16, height: 16)
            return custom
        }
        let sym = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: nil)
        sym?.isTemplate = true
        return sym
    }

    private func nsColor(_ severity: LimitSeverity) -> NSColor {
        switch severity {
        case .ok: return NSColor(calibratedRed: 0.20, green: 0.72, blue: 0.38, alpha: 1)
        case .low: return NSColor(calibratedRed: 0.92, green: 0.68, blue: 0.12, alpha: 1)
        case .critical: return NSColor(calibratedRed: 0.92, green: 0.28, blue: 0.26, alpha: 1)
        case .unknown: return NSColor.secondaryLabelColor
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(sender)
            removeMonitor()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.popover?.performClose(nil)
                self?.removeMonitor()
            }
        }
    }

    private func removeMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
}

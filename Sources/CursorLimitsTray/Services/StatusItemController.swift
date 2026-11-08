import AppKit
import SwiftUI
import Combine

/// AppKit status item with compact icon+% title near the notch.
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
        item.button?.setAccessibilityTitle("Tray AI limits")
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
            ? "Tray AI limits"
            : "Tray AI limits " + segments.map {
                "\($0.provider.accessibilityName) \($0.remainingPercent)%"
            }.joined(separator: ", ")
        button.setAccessibilityTitle(a11y)

        if segments.isEmpty {
            button.attributedTitle = NSAttributedString(string: "")
            button.image = appGlyph()
            button.imagePosition = .imageOnly
            return
        }

        // Icon+% strip only — no leading app glyph (saves notch space).
        button.image = nil
        button.imagePosition = .noImage
        button.attributedTitle = composedTitle(segments: segments)
    }

    private func composedTitle(segments: [MenuBarSegment]) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        let result = NSMutableAttributedString()
        let separator = NSAttributedString(
            string: " · ",
            attributes: [
                .font: font,
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )

        for (index, segment) in segments.enumerated() {
            if index > 0 { result.append(separator) }

            let color = nsColor(segment.severity)
            if let icon = symbolAttachment(
                name: segment.provider.symbolName,
                color: color,
                font: font
            ) {
                result.append(NSAttributedString(attachment: icon))
                result.append(NSAttributedString(
                    string: "\u{200A}", // hair space between icon and %
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

    private func symbolAttachment(name: String, color: NSColor, font: NSFont) -> NSTextAttachment? {
        let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }

        let size = base.size
        guard size.width > 0, size.height > 0 else { return nil }

        let tinted = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }

        let attachment = NSTextAttachment()
        attachment.image = tinted
        // Optical align with digit cap-height.
        let yOffset = (font.capHeight - size.height) / 2
        attachment.bounds = CGRect(x: 0, y: yOffset, width: size.width, height: size.height)
        return attachment
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

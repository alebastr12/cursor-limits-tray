import AppKit
import SwiftUI
import Combine

/// AppKit status item with compact live title near the notch.
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
        item.button?.imagePosition = .imageLeading
        item.button?.setAccessibilityTitle("Tray AI limits")
        statusItem = item

        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = true
        pop.contentSize = NSSize(width: 360, height: 280)
        pop.contentViewController = NSHostingController(rootView: PopoverView(poller: poller))
        popover = pop

        poller.$menuBarText
            .combineLatest(poller.$cursorConnected, poller.$chatGPTConnected, poller.$claudeConnected)
            .receive(on: RunLoop.main)
            .sink { [weak self] text, cOK, gOK, aOK in
                guard let self, let poller = self.poller else { return }
                self.applyTitle(
                    text,
                    cursor: poller.cursorSeverity,
                    chat: poller.chatGPTSeverity,
                    claude: poller.claudeSeverity
                )
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

        applyTitle(
            poller.menuBarText,
            cursor: poller.cursorSeverity,
            chat: poller.chatGPTSeverity,
            claude: poller.claudeSeverity
        )
        poller.start()
    }

    private func applyTitle(
        _ text: String,
        cursor: LimitSeverity,
        chat: LimitSeverity,
        claude: LimitSeverity
    ) {
        guard let button = statusItem?.button else { return }

        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let attr = NSMutableAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ])

        // Color whatever letters are actually present (no placeholders).
        colorSegment(in: attr, letter: "C", severity: cursor, font: font)
        colorSegment(in: attr, letter: "G", severity: chat, font: font)
        colorSegment(in: attr, letter: "A", severity: claude, font: font)

        button.attributedTitle = attr
        button.setAccessibilityTitle(text.isEmpty ? "Tray AI limits" : "Tray AI limits \(text)")

        let image: NSImage?
        if let url = Bundle.main.url(forResource: "MenuBarGlyph", withExtension: "png"),
           let custom = NSImage(contentsOf: url) {
            custom.isTemplate = true
            custom.size = NSSize(width: 16, height: 16)
            image = custom
        } else {
            let sym = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: nil)
            sym?.isTemplate = true
            image = sym
        }
        button.image = image
        button.imagePosition = text.isEmpty ? .imageOnly : .imageLeading
    }

    private func colorSegment(
        in attr: NSMutableAttributedString,
        letter: Character,
        severity: LimitSeverity,
        font: NSFont
    ) {
        let s = attr.string as NSString
        let full = s as String
        let pattern = "\(letter)[^ ·]+"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: full, range: NSRange(location: 0, length: s.length)) {
            attr.addAttributes([
                .foregroundColor: nsColor(severity),
                .font: font
            ], range: match.range)
        }
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

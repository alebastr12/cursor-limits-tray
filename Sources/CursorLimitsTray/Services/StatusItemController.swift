import AppKit
import SwiftUI
import Combine

/// Borderless non-activating panel that can sit above fullscreen Spaces.
private final class TrayStatusPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}

/// Clear overlay on the status button: carries `toolTip` (attributedTitle kills system tips)
/// and owns the click so toggle is reliable.
private final class StatusItemHitView: NSView {
    var onMouseDown: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
    }
}

/// AppKit status item with compact brand-icon + % title near the notch.
///
/// Uses `NSPanel` (not `NSPopover`) with `.canJoinAllSpaces` + `.fullScreenAuxiliary`
/// and main-menu level so the tray UI appears over fullscreen Spaces.
@MainActor
final class StatusItemController: NSObject {
    static let shared = StatusItemController()

    private var statusItem: NSStatusItem?
    private var panel: TrayStatusPanel?
    private var hosting: NSHostingController<AnyView>?
    private var hitView: StatusItemHitView?
    private var poller: UsagePoller?
    private var cancellables = Set<AnyCancellable>()
    private var eventMonitor: Any?
    private var panelHeight: CGFloat = 280
    /// Own flag — `NSPanel.isVisible` races with the global click monitor on status-item re-clicks.
    private var isPresented = false

    func install(poller: UsagePoller) {
        self.poller = poller

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Clicks + hover tip live on StatusItemHitView (button.toolTip fails with attributedTitle).
        item.button?.target = nil
        item.button?.action = nil
        item.button?.imagePosition = .imageOnly
        item.button?.setAccessibilityTitle(L10n.appName)
        statusItem = item

        if let button = item.button {
            let hit = StatusItemHitView(frame: button.bounds)
            hit.autoresizingMask = [.width, .height]
            hit.onMouseDown = { [weak self] in
                self?.togglePanel(nil)
            }
            button.addSubview(hit)
            hitView = hit
        }

        let root = AnyView(
            PopoverView(poller: poller)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor))
                )
        )
        let controller = NSHostingController(rootView: root)
        hosting = controller

        let panel = TrayStatusPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        panel.contentViewController = controller
        panel.title = "TrayAILimitsPanel"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = false
        panel.hasShadow = true
        // Opaque panel — no see-through corners / desktop bleed.
        panel.isOpaque = true
        panel.backgroundColor = .windowBackgroundColor
        panel.animationBehavior = .utilityWindow
        applyFullscreenPresentation(to: panel)
        self.panel = panel

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
                self.panelHeight = height
                if self.isPresented {
                    self.positionVisiblePanel()
                }
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

        let tip = UsagePoller.menuBarTooltip(segments: segments)
        // System toolTip on the button itself is unreliable with attributedTitle + attachments.
        button.toolTip = nil
        hitView?.toolTip = tip
        hitView?.frame = button.bounds

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

    /// Test / automation hook (DistributedNotification or `--show-panel`).
    func showPanelForProbe() {
        if isPresented { return }
        showPanel()
    }

    @objc private func togglePanel(_ sender: Any?) {
        if isPresented {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let panel else { return }
        // Avoid stacking monitors / double-open.
        if isPresented {
            positionVisiblePanel()
            return
        }
        isPresented = true
        positionVisiblePanel()
        applyFullscreenPresentation(to: panel)
        panel.orderFrontRegardless()
        applyFullscreenPresentation(to: panel)

        removeMonitor()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.isPresented else { return }
            // Status-item re-click: ignore here — `togglePanel` / hit view owns hide.
            if self.isClickOnStatusItem(event) { return }
            if let panel = self.panel, event.windowNumber == panel.windowNumber { return }
            self.hidePanel()
        }
    }

    private func hidePanel() {
        isPresented = false
        panel?.orderOut(nil)
        removeMonitor()
    }

    private func isClickOnStatusItem(_ event: NSEvent) -> Bool {
        guard let button = statusItem?.button else { return false }
        let screenPoint: NSPoint
        if let window = event.window {
            screenPoint = window.convertPoint(toScreen: event.locationInWindow)
        } else {
            // Global monitor events often have a nil window; locationInWindow is still screen-backed.
            screenPoint = event.locationInWindow
        }
        if let buttonWindow = button.window {
            let buttonScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
            if buttonScreen.insetBy(dx: -2, dy: -2).contains(screenPoint) {
                return true
            }
        }
        if let hit = hitView, let hitWindow = hit.window {
            let hitScreen = hitWindow.convertToScreen(hit.convert(hit.bounds, to: nil))
            return hitScreen.insetBy(dx: -2, dy: -2).contains(screenPoint)
        }
        return false
    }

    private func applyFullscreenPresentation(to panel: NSPanel) {
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle
        ]
        // `.mainMenu` floats above fullscreen content; `.floating` does not.
        panel.level = .mainMenu
        panel.isOpaque = true
        panel.backgroundColor = .windowBackgroundColor
    }

    private func positionVisiblePanel() {
        guard let panel, let button = statusItem?.button else { return }
        let size = NSSize(width: 360, height: panelHeight)
        hosting?.view.frame = NSRect(origin: .zero, size: size)
        panel.setContentSize(size)
        positionPanel(panel, relativeTo: button)
    }

    private func positionPanel(_ panel: NSPanel, relativeTo button: NSStatusBarButton) {
        let size = NSSize(width: 360, height: panelHeight)
        var anchor: NSRect?

        if let buttonWindow = button.window ?? button.superview?.window {
            let buttonRect = button.convert(button.bounds, to: nil)
            anchor = buttonWindow.convertToScreen(buttonRect)
        }

        let mouse = NSEvent.mouseLocation
        let anchorRect = anchor ?? NSRect(x: mouse.x - 10, y: mouse.y - 10, width: 20, height: 20)

        var origin = NSPoint(
            x: anchorRect.midX - size.width / 2,
            y: anchorRect.minY - size.height - 6
        )

        let screen = (button.window ?? button.superview?.window)?.screen
            ?? NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.main
        if let screen {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            if origin.y < visible.minY + 8 {
                origin.y = max(visible.minY + 8, anchorRect.maxY + 6)
            }
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
    }

    private func removeMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
}

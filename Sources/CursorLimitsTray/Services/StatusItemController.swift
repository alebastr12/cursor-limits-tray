import AppKit
import SwiftUI
import Combine

private let trayCornerRadius: CGFloat = 12

/// Borderless non-activating panel that can sit above fullscreen Spaces.
private final class TrayStatusPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}

/// Status-item overlay: click toggle + hover enter/exit (system `toolTip` is dead with attributedTitle).
private final class StatusItemHitView: NSView {
    var onMouseDown: (() -> Void)?
    var onHoverEnter: (() -> Void)?
    var onHoverExit: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onHoverExit?()
        onMouseDown?()
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverEnter?()
    }

    override func mouseExited(with event: NSEvent) {
        onHoverExit?()
    }
}

/// AppKit status item with compact brand-icon + % title near the notch.
@MainActor
final class StatusItemController: NSObject {
    static let shared = StatusItemController()

    private var statusItem: NSStatusItem?
    private var panel: TrayStatusPanel?
    private var hosting: NSHostingController<AnyView>?
    private var hitView: StatusItemHitView?
    private var tipPanel: NSPanel?
    private var tipLabel: NSTextField?
    private var tipText: String = ""
    private var tipShowWork: DispatchWorkItem?
    private var poller: UsagePoller?
    private var cancellables = Set<AnyCancellable>()
    private var eventMonitor: Any?
    private var panelHeight: CGFloat = 280
    /// Own flag — `NSPanel.isVisible` races with the global click monitor on status-item re-clicks.
    private var isPresented = false

    func install(poller: UsagePoller) {
        self.poller = poller

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
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
            hit.onHoverEnter = { [weak self] in
                self?.scheduleHoverTip()
            }
            hit.onHoverExit = { [weak self] in
                self?.hideHoverTip()
            }
            button.addSubview(hit)
            hitView = hit
        }

        let root = AnyView(
            PopoverView(poller: poller)
                .clipShape(RoundedRectangle(cornerRadius: trayCornerRadius, style: .continuous))
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
        // Clear window chrome; opaque rounded content is clipped by the hosting view layer.
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.animationBehavior = .utilityWindow
        applyFullscreenPresentation(to: panel)
        applyRoundedMask(to: panel)
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

        tipText = UsagePoller.menuBarTooltip(segments: segments)
        button.toolTip = nil
        hitView?.toolTip = nil
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
        let side: CGFloat = 15
        let size = NSSize(width: side, height: side)
        let tinted = NSImage(size: size, flipped: false) { rect in
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

    // MARK: - Hover tip (custom panel — system tooltips do not work on status items with attachments)

    private func scheduleHoverTip() {
        tipShowWork?.cancel()
        guard !isPresented, !tipText.isEmpty else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.showHoverTip()
        }
        tipShowWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func showHoverTip() {
        guard !isPresented, !tipText.isEmpty, let button = statusItem?.button else { return }
        let tip = ensureTipPanel()
        guard let tipLabel else { return }
        tipLabel.stringValue = tipText
        tipLabel.preferredMaxLayoutWidth = 280
        let labelSize = tipLabel.sizeThatFits(NSSize(width: 280, height: 10_000))
        let padding = NSSize(width: 20, height: 16)
        let size = NSSize(
            width: max(120, min(300, labelSize.width + padding.width)),
            height: max(28, labelSize.height + padding.height)
        )
        tip.setContentSize(size)
        tipLabel.frame = NSRect(
            x: padding.width / 2,
            y: padding.height / 2,
            width: size.width - padding.width,
            height: labelSize.height
        )

        var anchor: NSRect?
        if let buttonWindow = button.window {
            anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        }
        let mouse = NSEvent.mouseLocation
        let anchorRect = anchor ?? NSRect(x: mouse.x - 8, y: mouse.y - 8, width: 16, height: 16)
        var origin = NSPoint(
            x: anchorRect.midX - size.width / 2,
            y: anchorRect.minY - size.height - 4
        )
        if let screen = button.window?.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
            if origin.y < visible.minY + 4 {
                origin.y = anchorRect.maxY + 4
            }
        }
        tip.setFrame(NSRect(origin: origin, size: size), display: true)
        tip.orderFrontRegardless()
    }

    private func hideHoverTip() {
        tipShowWork?.cancel()
        tipShowWork = nil
        tipPanel?.orderOut(nil)
    }

    private func ensureTipPanel() -> NSPanel {
        if let tipPanel { return tipPanel }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.animationBehavior = .utilityWindow

        let root = NSView(frame: .zero)
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        root.layer?.cornerRadius = 8
        root.layer?.masksToBounds = true
        panel.contentView = root

        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 11)
        label.textColor = .labelColor
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 12
        label.isSelectable = false
        root.addSubview(label)

        tipLabel = label
        tipPanel = panel
        return panel
    }

    // MARK: - Main panel

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
        hideHoverTip()
        if isPresented {
            positionVisiblePanel()
            return
        }
        isPresented = true
        positionVisiblePanel()
        applyFullscreenPresentation(to: panel)
        applyRoundedMask(to: panel)
        panel.orderFrontRegardless()
        applyFullscreenPresentation(to: panel)
        applyRoundedMask(to: panel)

        removeMonitor()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.isPresented else { return }
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
        panel.level = .mainMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
    }

    private func applyRoundedMask(to panel: NSPanel) {
        guard let content = panel.contentView else { return }
        content.wantsLayer = true
        content.layer?.cornerRadius = trayCornerRadius
        content.layer?.masksToBounds = true
        content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        hosting?.view.wantsLayer = true
        hosting?.view.layer?.cornerRadius = trayCornerRadius
        hosting?.view.layer?.masksToBounds = true
    }

    private func positionVisiblePanel() {
        guard let panel, let button = statusItem?.button else { return }
        let size = NSSize(width: 360, height: panelHeight)
        hosting?.view.frame = NSRect(origin: .zero, size: size)
        panel.setContentSize(size)
        positionPanel(panel, relativeTo: button)
        applyRoundedMask(to: panel)
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

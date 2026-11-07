import AppKit
import WebKit

/// Floating login panel for claude.ai (same pattern as ChatGPT — survives tray popover dismiss).
@MainActor
final class ClaudeConnectController: NSObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    static let shared = ClaudeConnectController()

    private var panel: NSPanel?
    private var webView: WKWebView?
    private var statusLabel: NSTextField?
    private var onConnected: ((String) -> Void)?
    private var didEmit = false
    private var previousActivationPolicy: NSApplication.ActivationPolicy?

    func present(onConnected: @escaping (String) -> Void) {
        self.onConnected = onConnected
        didEmit = false
        if previousActivationPolicy == nil {
            previousActivationPolicy = NSApp.activationPolicy()
            NSApp.setActivationPolicy(.regular)
        }
        if let panel, panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let panel = makePanel()
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self, weak panel] in
            panel?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            self?.webView?.window?.makeFirstResponder(self?.webView)
        }
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
        webView = nil
        statusLabel = nil
        onConnected = nil
        if let previous = previousActivationPolicy {
            NSApp.setActivationPolicy(previous)
            previousActivationPolicy = nil
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 720),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Подключение Claude"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        panel.center()

        let root = NSView(frame: .zero)
        root.autoresizingMask = [.width, .height]

        let header = NSTextField(labelWithString: "Войдите в Claude. Окно не закроется при клике снаружи.")
        header.font = .systemFont(ofSize: 12)
        header.textColor = .secondaryLabelColor
        header.translatesAutoresizingMaskIntoConstraints = false
        statusLabel = header

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.translatesAutoresizingMaskIntoConstraints = false
        webView = web

        let check = NSButton(title: "Я уже вошёл — проверить", target: self, action: #selector(recheck))
        check.bezelStyle = .rounded
        check.translatesAutoresizingMaskIntoConstraints = false
        let closeBtn = NSButton(title: "Закрыть", target: self, action: #selector(closeClicked))
        closeBtn.bezelStyle = .rounded
        closeBtn.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(header)
        root.addSubview(web)
        root.addSubview(check)
        root.addSubview(closeBtn)
        panel.contentView = root

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            web.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            web.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            web.bottomAnchor.constraint(equalTo: check.topAnchor, constant: -10),
            closeBtn.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            closeBtn.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            check.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            check.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12)
        ])
        web.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        return panel
    }

    @objc private func recheck() {
        setStatus("Проверяю сессию…")
        inspectCookies()
    }

    @objc private func closeClicked() { close() }

    @objc func windowWillClose(_ notification: Notification) {
        panel = nil
        webView = nil
        statusLabel = nil
        onConnected = nil
        if let previous = previousActivationPolicy {
            NSApp.setActivationPolicy(previous)
            previousActivationPolicy = nil
        }
    }

    private func setStatus(_ text: String) { statusLabel?.stringValue = text }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.inspectCookies() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in self?.inspectCookies() }
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    private func inspectCookies() {
        guard let store = webView?.configuration.websiteDataStore.httpCookieStore else { return }
        store.getAllCookies { [weak self] cookies in
            Task { @MainActor in
                guard let self, !self.didEmit else { return }
                let relevant = cookies.filter {
                    $0.domain.contains("claude.ai") && ($0.name == "sessionKey" || $0.name == "sessionKeyV3")
                }
                guard let session = relevant.first(where: { $0.name == "sessionKey" })?.value
                        ?? relevant.first?.value,
                      session.hasPrefix("sk-ant") else {
                    self.setStatus("Сессии пока нет — войдите в Claude в окне выше.")
                    return
                }
                self.didEmit = true
                self.setStatus("Сессия найдена, сохраняю…")
                let header = "sessionKey=\(session)"
                self.onConnected?(header)
                self.close()
            }
        }
    }
}

import AppKit
import WebKit

/// Standalone login window for claude.ai (survives tray popover dismiss).
/// Uses a normal `NSWindow` (not floating NSPanel) so Settings stays clickable after close.
@MainActor
final class ClaudeConnectController: NSObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    static let shared = ClaudeConnectController()

    private var window: NSWindow?
    private var webView: WKWebView?
    private var statusLabel: NSTextField?
    private var onConnected: ((String) -> Void)?
    private var didEmit = false
    private var sessionStarted = false
    private var isClosing = false

    func present(onConnected: @escaping (String) -> Void) {
        self.onConnected = onConnected
        didEmit = false
        isClosing = false

        if !sessionStarted {
            sessionStarted = true
            TrayLifecycle.beginSessionWindow()
        }

        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self, weak window] in
            guard let self, !self.isClosing else { return }
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            self.webView?.window?.makeFirstResponder(self.webView)
        }
    }

    func close() {
        finishClosing(orderOut: true)
    }

    private func finishClosing(orderOut: Bool) {
        guard !isClosing else { return }
        isClosing = true

        let hadSession = sessionStarted
        sessionStarted = false

        if orderOut {
            window?.delegate = nil
            window?.orderOut(nil)
            window?.close()
        }
        window = nil
        webView = nil
        statusLabel = nil
        onConnected = nil

        if hadSession {
            TrayLifecycle.endSessionWindow()
        } else {
            TrayLifecycle.restoreKeyToBestUserWindow()
            TrayLifecycle.returnToTrayOnlyIfNoUserWindows()
        }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 720),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Подключение Claude"
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.minSize = NSSize(width: 560, height: 520)
        window.delegate = self
        window.center()

        let root = NSView(frame: .zero)
        root.translatesAutoresizingMaskIntoConstraints = false

        let header = NSTextField(labelWithString: "Войдите в Claude. После входа нажмите «проверить» или дождитесь авто-сохранения.")
        header.font = .systemFont(ofSize: 12)
        header.textColor = .secondaryLabelColor
        header.translatesAutoresizingMaskIntoConstraints = false
        statusLabel = header

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
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

        let content = NSView()
        content.addSubview(header)
        content.addSubview(web)
        content.addSubview(check)
        content.addSubview(closeBtn)
        window.contentView = content

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            header.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            web.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            web.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            web.bottomAnchor.constraint(equalTo: check.topAnchor, constant: -10),
            closeBtn.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            closeBtn.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            check.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            check.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
        ])
        web.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        return window
    }

    @objc private func recheck() {
        setStatus("Проверяю сессию…")
        inspectCookies()
    }

    @objc private func closeClicked() { close() }

    func windowWillClose(_ notification: Notification) {
        // Traffic-light / ⌘W — teardown once; don't orderOut again.
        finishClosing(orderOut: false)
    }

    private func setStatus(_ text: String) { statusLabel?.stringValue = text }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, !self.isClosing else { return }
            self.inspectCookies()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self, !self.isClosing else { return }
            self.inspectCookies()
        }
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
        guard !isClosing, let store = webView?.configuration.websiteDataStore.httpCookieStore else { return }
        store.getAllCookies { [weak self] cookies in
            Task { @MainActor in
                guard let self, !self.didEmit, !self.isClosing else { return }
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
                let callback = self.onConnected
                // Callback before close so Settings can update state while still .regular.
                callback?(header)
                self.close()
            }
        }
    }
}

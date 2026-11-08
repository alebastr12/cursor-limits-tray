import AppKit
import WebKit

/// Standalone login window for ChatGPT (survives tray popover dismiss).
/// Uses a normal `NSWindow` so Settings remains clickable after close (same freeze fix as Claude).
@MainActor
final class ChatGPTConnectController: NSObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    static let shared = ChatGPTConnectController()

    private var window: NSWindow?
    private var webView: WKWebView?
    private var statusLabel: NSTextField?
    private var onConnected: ((String) -> Void)?
    private var didEmit = false
    private var consentAttempts = 0
    private var sessionStarted = false
    private var isClosing = false

    func present(onConnected: @escaping (String) -> Void) {
        self.onConnected = onConnected
        didEmit = false
        consentAttempts = 0
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
        window.title = L10n.tr("connect.chatgpt.title")
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.minSize = NSSize(width: 560, height: 520)
        window.delegate = self
        window.center()

        let header = NSTextField(labelWithString: L10n.tr("connect.chatgpt.header"))
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

        let checkButton = NSButton(title: L10n.tr("connect.check"), target: self, action: #selector(recheck))
        checkButton.bezelStyle = .rounded
        checkButton.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = NSButton(title: L10n.close, target: self, action: #selector(closeClicked))
        closeButton.bezelStyle = .rounded
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(header)
        content.addSubview(web)
        content.addSubview(checkButton)
        content.addSubview(closeButton)
        window.contentView = content

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            header.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),

            web.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            web.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            web.bottomAnchor.constraint(equalTo: checkButton.topAnchor, constant: -10),

            closeButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            closeButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),

            checkButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            checkButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
        ])

        web.load(URLRequest(url: URL(string: "https://chatgpt.com")!))
        return window
    }

    @objc private func recheck() {
        setStatus(L10n.tr("connect.checking"))
        inspectCookies()
    }

    @objc private func closeClicked() {
        close()
    }

    func windowWillClose(_ notification: Notification) {
        finishClosing(orderOut: false)
    }

    private func setStatus(_ text: String) {
        statusLabel?.stringValue = text
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        tryAcceptCookieBanner(in: webView)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, !self.isClosing else { return }
            self.inspectCookies()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self, !self.isClosing else { return }
            self.tryAcceptCookieBanner(in: webView)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            guard let self, !self.isClosing else { return }
            self.tryAcceptCookieBanner(in: webView)
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(.allow)
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

    // MARK: - Consent + cookies

    private func tryAcceptCookieBanner(in webView: WKWebView) {
        consentAttempts += 1
        let js = """
        (function() {
          function clickIf(el) {
            if (!el) return false;
            el.click();
            return true;
          }
          const texts = [
            'accept all', 'accept', 'agree', 'allow all', 'got it', 'i agree',
            'принять все', 'принять', 'согласен', 'разрешить все', 'хорошо'
          ];
          const nodes = Array.from(document.querySelectorAll(
            'button, [role="button"], input[type="button"], input[type="submit"], a'
          ));
          for (const el of nodes) {
            const t = (el.innerText || el.textContent || el.value || '').trim().toLowerCase();
            if (!t) continue;
            for (const needle of texts) {
              if (t === needle || t.includes(needle)) {
                el.click();
                return 'clicked:' + t.slice(0, 40);
              }
            }
          }
          const ids = [
            'onetrust-accept-btn-handler',
            'accept-button',
            'acceptAllButton',
            'CybotCookiebotDialogBodyLevelButtonLevelOptinAllowAll'
          ];
          for (const id of ids) {
            if (clickIf(document.getElementById(id))) return 'clicked-id:' + id;
          }
          const root = document.querySelector('#onetrust-banner-sdk, #cookie-banner, [id*="cookie"], [class*="cookie"]');
          if (root) {
            const btn = root.querySelector('button');
            if (clickIf(btn)) return 'clicked-banner-btn';
          }
          return 'none';
        })();
        """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            if let s = result as? String, s.hasPrefix("clicked") {
                self?.setStatus(L10n.tr("connect.cookie_accepted"))
            }
        }
    }

    private func inspectCookies() {
        guard !isClosing, let store = webView?.configuration.websiteDataStore.httpCookieStore else { return }
        store.getAllCookies { [weak self] cookies in
            Task { @MainActor in
                guard let self, !self.didEmit, !self.isClosing else { return }
                let relevant = cookies.filter {
                    $0.domain.contains("chatgpt.com") && $0.name.contains("next-auth.session-token")
                }
                guard !relevant.isEmpty else {
                    self.setStatus(L10n.tr("connect.chatgpt.no_session"))
                    return
                }

                let byName = Dictionary(uniqueKeysWithValues: relevant.map { ($0.name, $0.value) })
                let header: String
                if let z = byName["__Secure-next-auth.session-token.0"],
                   let o = byName["__Secure-next-auth.session-token.1"] {
                    header = "__Secure-next-auth.session-token.0=\(z); __Secure-next-auth.session-token.1=\(o)"
                } else if let single = byName["__Secure-next-auth.session-token"] {
                    header = "__Secure-next-auth.session-token=\(single)"
                } else {
                    header = relevant.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                }

                self.didEmit = true
                self.setStatus(L10n.tr("connect.session_saving"))
                let callback = self.onConnected
                callback?(header)
                self.close()
            }
        }
    }
}

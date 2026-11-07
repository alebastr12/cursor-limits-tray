import AppKit
import WebKit

/// Owns a standalone floating login panel so MenuBarExtra popover dismissal
/// cannot tear down the ChatGPT connect UI mid-consent / mid-login.
@MainActor
final class ChatGPTConnectController: NSObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    static let shared = ChatGPTConnectController()

    private var panel: NSPanel?
    private var webView: WKWebView?
    private var statusLabel: NSTextField?
    private var onConnected: ((String) -> Void)?
    private var didEmit = false
    private var consentAttempts = 0

    private var previousActivationPolicy: NSApplication.ActivationPolicy?

    func present(onConnected: @escaping (String) -> Void) {
        self.onConnected = onConnected
        didEmit = false
        consentAttempts = 0

        // Accessory (menu-bar) apps often fail to deliver mouse events to sheets/panels.
        if previousActivationPolicy == nil {
            previousActivationPolicy = NSApp.activationPolicy()
            TrayLifecycle.beginShowingWindow()
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

        // Popover dismiss often races with panel presentation — re-assert key.
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
        previousActivationPolicy = nil
        // Closing login UI must not quit — return to tray-only if nothing else is open.
        TrayLifecycle.returnToTrayOnlyIfNoUserWindows()
    }

    // MARK: - UI

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 720),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Подключение ChatGPT"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.becomesKeyOnlyIfNeeded = false
        panel.worksWhenModal = true
        panel.minSize = NSSize(width: 560, height: 520)
        panel.delegate = self
        panel.center()

        let root = NSView(frame: panel.contentView!.bounds)
        root.autoresizingMask = [.width, .height]

        let header = NSTextField(labelWithString: "Войдите в ChatGPT. Окно не закроется при клике снаружи.")
        header.font = .systemFont(ofSize: 12)
        header.textColor = .secondaryLabelColor
        header.translatesAutoresizingMaskIntoConstraints = false
        statusLabel = header

        let config = WKWebViewConfiguration()
        // Persistent store so consent cookies stick during the login flow.
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.translatesAutoresizingMaskIntoConstraints = false
        webView = web

        let checkButton = NSButton(title: "Я уже вошёл — проверить", target: self, action: #selector(recheck))
        checkButton.bezelStyle = .rounded
        checkButton.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = NSButton(title: "Закрыть", target: self, action: #selector(closeClicked))
        closeButton.bezelStyle = .rounded
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(header)
        root.addSubview(web)
        root.addSubview(checkButton)
        root.addSubview(closeButton)
        panel.contentView = root

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),

            web.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            web.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            web.bottomAnchor.constraint(equalTo: checkButton.topAnchor, constant: -10),

            closeButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            closeButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),

            checkButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            checkButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12)
        ])

        web.load(URLRequest(url: URL(string: "https://chatgpt.com")!))
        return panel
    }

    @objc private func recheck() {
        setStatus("Проверяю сессию…")
        inspectCookies()
    }

    @objc private func closeClicked() {
        close()
    }

    @objc func windowWillClose(_ notification: Notification) {
        // Red traffic-light / Cmd+W — hide only; tray keeps polling.
        panel = nil
        webView = nil
        statusLabel = nil
        onConnected = nil
        previousActivationPolicy = nil
        DispatchQueue.main.async {
            TrayLifecycle.returnToTrayOnlyIfNoUserWindows()
        }
    }

    private func setStatus(_ text: String) {
        statusLabel?.stringValue = text
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        tryAcceptCookieBanner(in: webView)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.inspectCookies()
        }
        // Cookie banners often mount late.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.tryAcceptCookieBanner(in: webView)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            self?.tryAcceptCookieBanner(in: webView)
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        // Keep OAuth / consent navigations inside this window when possible.
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // OpenAI sometimes opens consent/login in a target=_blank — load in-place.
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
          // OneTrust / common CMP ids
          const ids = [
            'onetrust-accept-btn-handler',
            'accept-button',
            'acceptAllButton',
            'CybotCookiebotDialogBodyLevelButtonLevelOptinAllowAll'
          ];
          for (const id of ids) {
            if (clickIf(document.getElementById(id))) return 'clicked-id:' + id;
          }
          // Shadow / nested consent roots
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
                self?.setStatus("Cookie-баннер принят автоматически. Войдите в аккаунт…")
            }
        }
    }

    private func inspectCookies() {
        guard let store = webView?.configuration.websiteDataStore.httpCookieStore else { return }
        store.getAllCookies { [weak self] cookies in
            Task { @MainActor in
                guard let self, !self.didEmit else { return }
                let relevant = cookies.filter {
                    $0.domain.contains("chatgpt.com") && $0.name.contains("next-auth.session-token")
                }
                guard !relevant.isEmpty else {
                    self.setStatus("Сессии пока нет — примите cookies (если остались) и войдите.")
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
                self.setStatus("Сессия найдена, сохраняю…")
                let callback = self.onConnected
                callback?(header)
                self.close()
            }
        }
    }
}

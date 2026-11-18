import AppKit
import WebKit

/// Shared login window for ChatGPT / Claude.
///
/// A normal `NSWindow` (not a floating panel) so Settings stays clickable after
/// the login window closes. The persistent `.default()` WebKit store keeps the
/// session for the cookie bridge used by the poller.
@MainActor
final class WebLoginController: NSObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    enum Kind {
        case chatGPT
        case claude

        var title: String {
            switch self {
            case .chatGPT: return L10n.tr("connect.chatgpt.title")
            case .claude: return L10n.tr("connect.claude.title")
            }
        }

        var header: String {
            switch self {
            case .chatGPT: return L10n.tr("connect.chatgpt.header")
            case .claude: return L10n.tr("connect.claude.header")
            }
        }

        var startURL: URL {
            switch self {
            case .chatGPT: return URL(string: "https://chatgpt.com")!
            case .claude: return URL(string: "https://claude.ai/login")!
            }
        }

        var noSessionMessage: String {
            switch self {
            case .chatGPT: return L10n.tr("connect.chatgpt.no_session")
            case .claude: return L10n.tr("connect.claude.no_session")
            }
        }

        var acceptsCookieBanner: Bool { self == .chatGPT }

        /// Cookie auto-save attempts after the page finished loading.
        var inspectDelays: [TimeInterval] {
            switch self {
            case .chatGPT: return [1.0]
            case .claude: return [1.0, 3.0]
            }
        }

        /// Cookie-banner auto-accept attempts (ChatGPT only).
        var bannerDelays: [TimeInterval] {
            switch self {
            case .chatGPT: return [2.0, 4.0]
            case .claude: return []
            }
        }
    }

    private let kind: Kind
    private var window: NSWindow?
    private var webView: WKWebView?
    private var statusLabel: NSTextField?
    private var onConnected: ((String) -> Void)?
    private var didEmit = false
    private var sessionStarted = false
    private var isClosing = false

    init(kind: Kind) {
        self.kind = kind
        super.init()
    }

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
        window.title = kind.title
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.minSize = NSSize(width: 560, height: 520)
        window.delegate = self
        window.center()

        let header = NSTextField(labelWithString: kind.header)
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

        web.load(URLRequest(url: kind.startURL))
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
        if kind.acceptsCookieBanner {
            tryAcceptCookieBanner(in: webView)
        }
        for delay in kind.inspectDelays {
            schedule(after: delay) { $0.inspectCookies() }
        }
        for delay in kind.bannerDelays {
            schedule(after: delay) { $0.tryAcceptCookieBanner(in: webView) }
        }
    }

    private func schedule(after delay: TimeInterval, _ action: @escaping (WebLoginController) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.isClosing else { return }
            action(self)
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
                guard let header = self.sessionHeader(from: cookies) else {
                    self.setStatus(self.kind.noSessionMessage)
                    return
                }

                self.didEmit = true
                self.setStatus(L10n.tr("connect.session_saving"))
                let callback = self.onConnected
                callback?(header)
                self.close()
            }
        }
    }

    private func sessionHeader(from cookies: [HTTPCookie]) -> String? {
        switch kind {
        case .chatGPT:
            // Keep every chatgpt.com cookie: workspace routing needs `_account`
            // and OpenAI's routing ids, not just the NextAuth token.
            return WebKitCookieBridge.chatGPTCookieHeader(from: cookies)

        case .claude:
            let relevant = cookies.filter {
                $0.domain.contains("claude.ai") && ($0.name == "sessionKey" || $0.name == "sessionKeyV3")
            }
            guard let session = relevant.first(where: { $0.name == "sessionKey" })?.value
                    ?? relevant.first?.value,
                  session.hasPrefix("sk-ant")
            else { return nil }
            return "sessionKey=\(session)"
        }
    }
}

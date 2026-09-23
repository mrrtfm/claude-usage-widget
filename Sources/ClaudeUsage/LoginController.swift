import AppKit
import WebKit
import os
import ClaudeUsageKit

private let log = Logger(subsystem: "com.laszlo.ClaudeUsage", category: "login")

// hosts claude.ai's real login page in a webview. the user signs in however they
// like — "continue with google" is a button on that page — and we scrape the
// resulting session cookie jar. one successful login == one account.
@MainActor
final class LoginController: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, NSWindowDelegate {
    private var window: NSWindow?
    private var webView: WKWebView!
    private var popupWindow: NSWindow?
    private var popupWebView: WKWebView?
    private var poll: Timer?
    private var finished = false
    private let completion: (Result<Account, Error>) -> Void

    struct Cancelled: Error {}

    init(completion: @escaping (Result<Account, Error>) -> Void) {
        self.completion = completion
        super.init()
    }

    func present() {
        let config = WKWebViewConfiguration()
        // ephemeral store so each "add account" starts logged-out — lets you pick a
        // different google account instead of silently reusing the last session.
        config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        // pipe the page's console + any ?error= param back to os_log for diagnosis
        let src = """
        (function(){
          function post(m){ try{ window.webkit.messageHandlers.log.postMessage(String(m)); }catch(e){} }
          ['log','warn','error'].forEach(function(k){ var o=console[k]; console[k]=function(){ post(k+': '+Array.from(arguments).join(' ')); o.apply(console,arguments); }; });
          if (location.search) post('query: '+location.search);
        })();
        """
        let user = WKUserScript(source: src, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(user)
        config.userContentController.add(self, name: "log")

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 460, height: 640), configuration: config)
        // no UA spoofing: a hand-written UA that doesn't match the real WebKit engine makes
        // claude's integrity check (and google's oauth) reject the login. use webkit's native
        // Safari UA and capture the exact string later for cf_clearance-matched api replay.
        webView.navigationDelegate = self
        webView.uiDelegate = self   // required so "continue with google" popups actually open

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 640),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        win.title = "Sign in to Claude"
        win.titlebarAppearsTransparent = true
        win.isReleasedWhenClosed = false   // we hold it in ARC; default true → double-free on close()
        win.contentView = webView
        win.center()
        win.delegate = self
        window = win

        NSApp.setActivationPolicy(.regular)  // temporarily show in dock so the window can take focus
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)

        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))

        // backup poll: some sessions land without a navigation callback firing
        poll = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkCookies() }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        log.debug("nav finished: \(webView.url?.absoluteString ?? "?", privacy: .public)")
        checkCookies()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        log.error("nav failed: \(error.localizedDescription, privacy: .public)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        log.error("provisional nav failed: \(error.localizedDescription, privacy: .public)")
    }

    // MARK: popups — google/apple oauth open a second window via window.open.
    // without this the popup never opens and claude reports "error logging you in".

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // share `configuration` (same process pool + cookie jar) so the oauth callback's
        // cookies land in the jar we're watching.
        let popup = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 660), configuration: configuration)
        popup.navigationDelegate = self
        popup.uiDelegate = self
        popupWebView = popup

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 660),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
        )
        win.title = "Continue sign-in"
        win.isReleasedWhenClosed = false   // same double-free trap as the main window
        win.contentView = popup
        win.center()
        win.makeKeyAndOrderFront(nil)
        popupWindow = win
        log.info("opened oauth popup for \(navigationAction.request.url?.host ?? "?", privacy: .public)")
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        // popup closed itself → oauth handshake done; re-check the cookie jar
        log.info("oauth popup closed")
        popupWindow?.close(); popupWindow = nil; popupWebView = nil
        checkCookies()
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        log.info("page: \(String(describing: message.body), privacy: .public)")
    }

    private func checkCookies() {
        guard !finished else { return }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            Task { @MainActor in
                guard let self, !self.finished else { return }
                let jar = cookies.filter { $0.domain.contains("claude.ai") }
                let map = Dictionary(jar.map { ($0.name, $0.value) }, uniquingKeysWith: { _, b in b })
                // sessionKey is the real credential; wait until it's populated
                guard let sk = map["sessionKey"], sk.count > 20 else { return }
                self.finalize(cookies: map)
            }
        }
    }

    private func finalize(cookies: [String: String]) {
        finished = true
        poll?.invalidate(); poll = nil
        Task {
            do {
                // grab the webview's real UA so api replay matches the cf_clearance cookie
                let ua = try? await webView.evaluateJavaScript("navigator.userAgent") as? String
                let id = try await ClaudeAPI.fetchIdentity(cookies: cookies, userAgent: ua)
                let account = Account(
                    id: id.orgUuid, name: id.name, email: id.email,
                    orgUuid: id.orgUuid, planTier: id.planTier, cookies: cookies, userAgent: ua
                )
                await MainActor.run { self.close(with: .success(account)) }
            } catch {
                log.error("bootstrap after login failed: \(error.localizedDescription, privacy: .public)")
                // cookie showed up but bootstrap failed — let the user keep trying
                await MainActor.run {
                    self.finished = false
                    self.poll = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                        Task { @MainActor in self?.checkCookies() }
                    }
                }
            }
        }
    }

    private func close(with result: Result<Account, Error>) {
        poll?.invalidate(); poll = nil
        window?.delegate = nil
        window?.close()
        window = nil
        NSApp.setActivationPolicy(.accessory)  // back to menu-bar-only
        completion(result)
    }

    func windowWillClose(_ notification: Notification) {
        guard !finished else { return }
        finished = true
        close(with: .failure(Cancelled()))
    }
}

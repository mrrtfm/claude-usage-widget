import SwiftUI
import UIKit
import WebKit
import os
import ClaudeUsageKit

private let log = Logger(subsystem: "com.laszlo.ClaudeUsage", category: "login")

// hosts claude.ai's real login page in a webview. the user signs in however they like —
// "continue with google" is a button on that page — and we scrape the resulting session
// cookie jar. one successful login == one account. straight port of the macOS
// LoginController; the only real difference is that oauth popups become a subview here
// instead of a second window.
final class LoginViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    private var webView: WKWebView!
    private var popupWebView: WKWebView?
    private var poll: Timer?
    private var finished = false
    private let completion: (Result<Account, Error>) -> Void

    struct Cancelled: Error {}

    init(completion: @escaping (Result<Account, Error>) -> Void) {
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

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
        config.userContentController.addUserScript(
            WKUserScript(source: src, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        config.userContentController.add(self, name: "log")

        // no UA spoofing: a hand-written UA that doesn't match the real WebKit engine makes
        // claude's integrity check (and google's oauth) reject the login. use webkit's native
        // Safari UA and capture the exact string later for cf_clearance-matched api replay.
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self   // required so "continue with google" popups actually open
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))

        // backup poll: some sessions land without a navigation callback firing
        poll = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkCookies() }
        }
    }

    // the sheet was swiped away without a session — tell the store so it can drop us
    func cancel() {
        guard !finished else { return }
        finished = true
        poll?.invalidate(); poll = nil
        completion(.failure(Cancelled()))
    }

    // MARK: navigation

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
        let popup = WKWebView(frame: view.bounds, configuration: configuration)
        popup.navigationDelegate = self
        popup.uiDelegate = self
        popup.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(popup)
        NSLayoutConstraint.activate([
            popup.topAnchor.constraint(equalTo: view.topAnchor),
            popup.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            popup.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            popup.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        popupWebView = popup
        log.info("opened oauth popup for \(navigationAction.request.url?.host ?? "?", privacy: .public)")
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        // popup closed itself → oauth handshake done; re-check the cookie jar
        log.info("oauth popup closed")
        popupWebView?.removeFromSuperview(); popupWebView = nil
        checkCookies()
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        log.info("page: \(String(describing: message.body), privacy: .public)")
    }

    // MARK: cookie capture

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
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                // grab the webview's real UA so api replay matches the cf_clearance cookie
                let ua = try? await self.webView.evaluateJavaScript("navigator.userAgent") as? String
                let id = try await ClaudeAPI.fetchIdentity(cookies: cookies, userAgent: ua)
                self.completion(.success(Account(
                    id: id.orgUuid, name: id.name, email: id.email,
                    orgUuid: id.orgUuid, planTier: id.planTier, cookies: cookies, userAgent: ua
                )))
            } catch {
                log.error("bootstrap after login failed: \(error.localizedDescription, privacy: .public)")
                // cookie showed up but bootstrap failed — let the user keep trying
                self.finished = false
                self.poll = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.checkCookies() }
                }
            }
        }
    }
}

// SwiftUI wrapper — presented as a sheet from ContentView.
struct LoginWebView: UIViewControllerRepresentable {
    let onFinish: (Result<Account, Error>) -> Void

    func makeUIViewController(context: Context) -> LoginViewController {
        LoginViewController(completion: onFinish)
    }

    func updateUIViewController(_ controller: LoginViewController, context: Context) {}

    // swiping the sheet down destroys the controller without ever calling completion —
    // settle it here so the store doesn't sit waiting on a login that will never land.
    static func dismantleUIViewController(_ controller: LoginViewController, coordinator: ()) {
        controller.cancel()
    }
}

import SwiftUI
import UIKit
import WebKit

/// Hosts the wallet UI in a WKWebView and gives the page two native bridges:
///
/// * `net`    — the page is loaded from `file://`, so `fetch()` to CoinGecko would be
///              blocked by CORS. The page posts `{id, url}`; we fetch with URLSession and
///              hand the body back via `window.__netResolve(id, ok, body)`.
/// * `haptic` — the page posts a style name ("light", "medium", "selection",
///              "success", "warning") and we play the matching Taptic Engine feedback.
/// * `open`   — the page posts an https URL (Ledger Support, shop, Discover
///              providers); we hand it to Safari instead of leaving the app.
/// * `share`  — the page posts `{name, text}` (Settings › Help › Export data); we
///              write it to a temporary .json file and show the share sheet.
struct WalletWebView: UIViewRepresentable {

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = .default()          // localStorage persists across launches

        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "net")
        controller.add(context.coordinator, name: "haptic")
        controller.add(context.coordinator, name: "open")
        controller.add(context.coordinator, name: "share")
        config.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: config)
        context.coordinator.webView = webView
        webView.uiDelegate = context.coordinator          // window.open → Safari
        webView.navigationDelegate = context.coordinator  // external links → Safari

        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.insetsLayoutMarginsFromSafeArea = false   // no black band under the home indicator
        webView.scrollView.contentInset = .zero
        webView.scrollView.bounces = false               // the page owns scrolling + pull-to-refresh
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        if #available(iOS 16.4, *) { webView.isInspectable = true }

        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "www") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            assertionFailure("www/index.html missing — check it is a folder reference in Copy Bundle Resources")
        }

        context.coordinator.observeForeground()
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate {
        weak var webView: WKWebView?

        private let session: URLSession = {
            let c = URLSessionConfiguration.default
            c.timeoutIntervalForRequest = 20
            c.waitsForConnectivity = false
            c.requestCachePolicy = .reloadIgnoringLocalCacheData
            return URLSession(configuration: c)
        }()

        private let light = UIImpactFeedbackGenerator(style: .light)
        private let medium = UIImpactFeedbackGenerator(style: .medium)
        private let selection = UISelectionFeedbackGenerator()
        private let notify = UINotificationFeedbackGenerator()

        func observeForeground() {
            NotificationCenter.default.addObserver(
                self, selector: #selector(didForeground),
                name: UIApplication.willEnterForegroundNotification, object: nil)
        }

        @objc private func didForeground() {
            webView?.evaluateJavaScript("window.__refresh && window.__refresh();")
        }

        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            switch message.name {
            case "haptic": playHaptic(message.body as? String ?? "light")
            case "net":    handleNet(message.body)
            case "open":   openExternal(message.body as? String)
            case "share":  share(message.body)
            default:       break
            }
        }

        private func playHaptic(_ style: String) {
            switch style {
            case "selection": selection.selectionChanged()
            case "medium":    medium.impactOccurred()
            case "success":   notify.notificationOccurred(.success)
            case "warning":   notify.notificationOccurred(.warning)
            default:          light.impactOccurred()
            }
        }

        private func openExternal(_ string: String?) {
            guard let string, let url = URL(string: string),
                  ["https", "mailto"].contains(url.scheme?.lowercased() ?? "") else { return }
            UIApplication.shared.open(url)
        }

        /// Writes the exported backup to a temp file and presents the iOS share sheet.
        private func share(_ raw: Any) {
            guard let body = raw as? [String: Any],
                  let text = body["text"] as? String,
                  let webView else { return }
            let rawName = (body["name"] as? String) ?? "wallet-backup.json"
            let safe = rawName.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "-", options: .regularExpression)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(safe.isEmpty ? "wallet-backup.json" : safe)
            do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { return }
            let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            sheet.popoverPresentationController?.sourceView = webView
            sheet.popoverPresentationController?.sourceRect = CGRect(x: webView.bounds.midX, y: webView.bounds.maxY - 80, width: 1, height: 1)
            var top = webView.window?.rootViewController
            while let presented = top?.presentedViewController { top = presented }
            top?.present(sheet, animated: true)
        }

        // target=_blank / window.open: open in Safari rather than a blank in-app view
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url { openExternal(url.absoluteString) }
            return nil
        }

        // keep the app on its bundled page; anything on the web goes to Safari
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url, url.scheme == "https" || url.scheme == "http",
               navigationAction.navigationType == .linkActivated {
                openExternal(url.absoluteString)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        private func handleNet(_ raw: Any) {
            guard let body = raw as? [String: Any],
                  let id = body["id"] as? Int,
                  let urlString = body["url"] as? String,
                  let url = URL(string: urlString),
                  url.scheme?.lowercased() == "https"
            else { return }

            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            session.dataTask(with: request) { [weak self] data, response, error in
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                let ok = error == nil && (200..<300).contains(code)
                let text = (ok ? data.flatMap { String(data: $0, encoding: .utf8) } : nil) ?? ""
                DispatchQueue.main.async {
                    self?.resolve(id: id, ok: ok, payload: text)
                }
            }.resume()
        }

        private func resolve(id: Int, ok: Bool, payload: String) {
            guard let webView else { return }
            let js = "window.__netResolve && window.__netResolve(\(id), \(ok), \(Self.jsLiteral(payload)));"
            webView.evaluateJavaScript(js)
        }

        /// JSON-escapes a string into a JS string literal (quotes included).
        static func jsLiteral(_ s: String) -> String {
            guard let data = try? JSONSerialization.data(withJSONObject: [s]),
                  let wrapped = String(data: data, encoding: .utf8),
                  wrapped.count >= 2
            else { return "\"\"" }
            return String(wrapped.dropFirst().dropLast())   // strip the [ ]
        }
    }
}

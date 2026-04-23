import Foundation
import WebKit

@MainActor
final class EmbeddedWebViewRuntime: NSObject {
    struct EventHandlers {
        var onNavigationStarted: ((URL?) -> Void)?
        var onNavigationCommitted: ((URL?) -> Void)?
        var onNavigationFinished: ((URL?) -> Void)?
        var onNavigationFailed: ((URL?, String) -> Void)?
    }

    let webView: WKWebView
    let retainedSurface: RetainedHostedSurface<WKWebView>
    var handlers = EventHandlers()
    private(set) var lastRequestedAddress: String?

    private var destinationByNavigation: [ObjectIdentifier: URL] = [:]

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        retainedSurface = RetainedHostedSurface(view: webView)
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
    }

    func load(_ url: URL) {
        lastRequestedAddress = url.absoluteString
        let navigation = webView.load(URLRequest(url: url))
        if let navigation {
            destinationByNavigation[ObjectIdentifier(navigation)] = url
        }
        handlers.onNavigationStarted?(url)
    }

    func loadIfNeeded(_ url: URL) {
        guard lastRequestedAddress != url.absoluteString else {
            return
        }
        load(url)
    }

    func resetToBlank() {
        lastRequestedAddress = nil
        webView.loadHTMLString("", baseURL: nil)
    }

    func invalidateLastRequestedAddress() {
        lastRequestedAddress = nil
    }

    private func destination(for navigation: WKNavigation?) -> URL? {
        guard let navigation else {
            return webView.url
        }
        return destinationByNavigation[ObjectIdentifier(navigation)] ?? webView.url
    }

    private func clearDestination(for navigation: WKNavigation?) {
        guard let navigation else {
            return
        }
        destinationByNavigation.removeValue(forKey: ObjectIdentifier(navigation))
    }
}

extension EmbeddedWebViewRuntime: WKNavigationDelegate {
    nonisolated func webView(
        _ webView: WKWebView,
        didStartProvisionalNavigation navigation: WKNavigation!
    ) {
        Task { @MainActor in
            self.handlers.onNavigationStarted?(self.destination(for: navigation))
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!
    ) {
        Task { @MainActor in
            self.handlers.onNavigationCommitted?(webView.url)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        Task { @MainActor in
            self.handlers.onNavigationCommitted?(webView.url)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.handlers.onNavigationFinished?(webView.url)
            self.clearDestination(for: navigation)
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        Task { @MainActor in
            self.handlers.onNavigationFailed?(self.destination(for: navigation), error.localizedDescription)
            self.clearDestination(for: navigation)
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        Task { @MainActor in
            self.handlers.onNavigationFailed?(self.destination(for: navigation), error.localizedDescription)
            self.clearDestination(for: navigation)
        }
    }
}

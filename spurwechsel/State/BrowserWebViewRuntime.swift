import Foundation
import WebKit
import os

@MainActor
final class EmbeddedWebViewRuntime: NSObject {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "dev.breuer.spurwechsel",
        category: "VSCodeDebug"
    )
    private static func trace(_ message: String) {
        #if DEBUG
        print("[VSCodeDebug][BrowserWebViewRuntime] \(message)")
        #else
        logger.debug("\(message, privacy: .public)")
        #endif
    }

    enum RequestedAddressState: Equatable {
        case loadingRequestedAddress
        case showingRequestedAddress
        case notShowingRequestedAddress
    }

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
    private(set) var isLoading = false

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
        Self.trace("load url=\(url.absoluteString)")
        lastRequestedAddress = url.absoluteString
        isLoading = true
        let navigation = webView.load(URLRequest(url: url))
        if let navigation {
            destinationByNavigation[ObjectIdentifier(navigation)] = url
        }
        handlers.onNavigationStarted?(url)
    }

    @discardableResult
    func loadIfNeeded(_ url: URL) -> Bool {
        guard lastRequestedAddress != url.absoluteString else {
            Self.trace("loadIfNeeded skip sameURL requested=\(url.absoluteString) webViewURL=\(webView.url?.absoluteString ?? "nil") isLoading=\(isLoading)")
            return false
        }
        Self.trace("loadIfNeeded trigger requested=\(url.absoluteString) prevRequested=\(lastRequestedAddress ?? "nil") webViewURL=\(webView.url?.absoluteString ?? "nil")")
        load(url)
        return true
    }

    func resetToBlank() {
        lastRequestedAddress = nil
        isLoading = false
        webView.loadHTMLString("", baseURL: nil)
    }

    func invalidateLastRequestedAddress() {
        lastRequestedAddress = nil
    }

    func requestedAddressState(for requestedAddress: String) -> RequestedAddressState {
        if isLoading, lastRequestedAddress == requestedAddress {
            Self.trace("requestedAddressState loading requested=\(requestedAddress) webViewURL=\(webView.url?.absoluteString ?? "nil")")
            return .loadingRequestedAddress
        }

        if webView.url?.absoluteString == requestedAddress {
            Self.trace("requestedAddressState showing requested=\(requestedAddress)")
            return .showingRequestedAddress
        }

        Self.trace("requestedAddressState miss requested=\(requestedAddress) lastRequested=\(lastRequestedAddress ?? "nil") webViewURL=\(webView.url?.absoluteString ?? "nil") isLoading=\(isLoading)")
        return .notShowingRequestedAddress
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
            self.isLoading = true
            Self.trace("delegate didStartProvisionalNavigation url=\(self.destination(for: navigation)?.absoluteString ?? "nil")")
            self.handlers.onNavigationStarted?(self.destination(for: navigation))
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!
    ) {
        Task { @MainActor in
            Self.trace("delegate didReceiveServerRedirect url=\(webView.url?.absoluteString ?? "nil")")
            self.handlers.onNavigationCommitted?(webView.url)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        Task { @MainActor in
            Self.trace("delegate didCommit url=\(webView.url?.absoluteString ?? "nil")")
            self.handlers.onNavigationCommitted?(webView.url)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.isLoading = false
            Self.trace("delegate didFinish url=\(webView.url?.absoluteString ?? "nil")")
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
            self.isLoading = false
            Self.trace("delegate didFail url=\(self.destination(for: navigation)?.absoluteString ?? "nil") error=\(error.localizedDescription)")
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
            self.isLoading = false
            Self.trace("delegate didFailProvisional url=\(self.destination(for: navigation)?.absoluteString ?? "nil") error=\(error.localizedDescription)")
            self.handlers.onNavigationFailed?(self.destination(for: navigation), error.localizedDescription)
            self.clearDestination(for: navigation)
        }
    }
}

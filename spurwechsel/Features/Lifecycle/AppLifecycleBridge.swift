import AppKit
import Foundation

@MainActor
final class AppLifecycleBridge {
    static let shared = AppLifecycleBridge()

    private var didFinishLaunchingHandler: @MainActor @Sendable () -> Void = {}
    private var openURLsHandler: @MainActor @Sendable ([URL]) -> Void = { _ in }
    private var terminationRequestedHandler: @MainActor @Sendable (UUID) -> Void = { _ in }

    private var isConnected = false
    private var launchedBeforeConnect = false
    private var pendingURLs: [URL] = []
    private var pendingTerminationReplies: [UUID: (Bool) -> Void] = [:]

    func connect(
        didFinishLaunching: @escaping @MainActor @Sendable () -> Void,
        openURLs: @escaping @MainActor @Sendable ([URL]) -> Void,
        requestTermination: @escaping @MainActor @Sendable (UUID) -> Void
    ) {
        didFinishLaunchingHandler = didFinishLaunching
        openURLsHandler = openURLs
        terminationRequestedHandler = requestTermination
        isConnected = true

        if launchedBeforeConnect {
            launchedBeforeConnect = false
            didFinishLaunchingHandler()
        }

        if !pendingURLs.isEmpty {
            let urls = pendingURLs
            pendingURLs.removeAll()
            openURLsHandler(urls)
        }
    }

    func applicationDidFinishLaunching() {
        guard isConnected else {
            launchedBeforeConnect = true
            return
        }

        didFinishLaunchingHandler()
    }

    func open(urls: [URL]) {
        guard !urls.isEmpty else {
            return
        }

        guard isConnected else {
            pendingURLs.append(contentsOf: urls)
            return
        }

        openURLsHandler(urls)
    }

    func requestTermination(reply: @escaping (Bool) -> Void) -> NSApplication.TerminateReply {
        guard isConnected else {
            return .terminateNow
        }

        guard pendingTerminationReplies.isEmpty else {
            return .terminateLater
        }

        let requestID = UUID()
        pendingTerminationReplies[requestID] = reply
        terminationRequestedHandler(requestID)
        return .terminateLater
    }

    func completeTerminationRequest(_ requestID: UUID, shouldTerminate: Bool) {
        guard let reply = pendingTerminationReplies.removeValue(forKey: requestID) else {
            return
        }

        reply(shouldTerminate)
    }
}
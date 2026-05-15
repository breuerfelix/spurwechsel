import AppKit
import Foundation
import os

@MainActor
final class AppLifecycleBridge {
    static let shared = AppLifecycleBridge()
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "dev.breuer.spurwechsel",
        category: "AppLifecycleBridge"
    )
    private static func trace(_ message: String) {
        #if DEBUG
        print("[LifecycleBridge] \(message)")
        #else
        logger.debug("\(message, privacy: .public)")
        #endif
    }

    private var didFinishLaunchingHandler: @MainActor @Sendable () -> Void = {}
    private var openURLsHandler: @MainActor @Sendable ([URL]) -> Void = { _ in }
    private var terminationRequestedHandler: @MainActor @Sendable (UUID) -> Void = { _ in }

    private var isConnected = false
    private var launchedBeforeConnect = false
    private var pendingURLs: [URL] = []
    private var allowImmediateApplicationTermination = false
    private var pendingTerminationRequestID: UUID?
    private var pendingTerminationReplies: [(Bool) -> Void] = []
    private var shouldTerminateApplicationOnCompletion = false

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
        if allowImmediateApplicationTermination {
            allowImmediateApplicationTermination = false
            Self.trace("requestTermination immediate terminateNow preapproved")
            return .terminateNow
        }

        guard isConnected else {
            Self.trace("requestTermination immediate terminateNow bridge not connected")
            return .terminateNow
        }

        if let existingRequestID = pendingTerminationRequestID {
            pendingTerminationReplies.append(reply)
            Self.trace("requestTermination coalesced requestID=\(existingRequestID.uuidString) replyCount=\(pendingTerminationReplies.count)")
            return .terminateLater
        }

        let requestID = UUID()
        pendingTerminationRequestID = requestID
        pendingTerminationReplies = [reply]
        shouldTerminateApplicationOnCompletion = false
        Self.trace("requestTermination started requestID=\(requestID.uuidString)")
        Self.trace("requestTermination dispatching handler requestID=\(requestID.uuidString)")
        terminationRequestedHandler(requestID)
        return .terminateLater
    }

    func requestTerminationFromWindowClose() -> Bool {
        guard isConnected else {
            Self.trace("requestTerminationFromWindowClose bridge not connected; falling back to NSApp.terminate(nil)")
            NSApp.terminate(nil)
            return false
        }

        if let existingRequestID = pendingTerminationRequestID {
            shouldTerminateApplicationOnCompletion = true
            Self.trace("requestTerminationFromWindowClose coalesced requestID=\(existingRequestID.uuidString)")
            return false
        }

        let requestID = UUID()
        pendingTerminationRequestID = requestID
        pendingTerminationReplies.removeAll()
        shouldTerminateApplicationOnCompletion = true
        Self.trace("requestTerminationFromWindowClose started requestID=\(requestID.uuidString)")
        Self.trace("requestTerminationFromWindowClose dispatching handler requestID=\(requestID.uuidString)")
        terminationRequestedHandler(requestID)
        return false
    }

    func completeTerminationRequest(_ requestID: UUID, shouldTerminate: Bool) {
        guard requestID == pendingTerminationRequestID else {
            let pendingID = pendingTerminationRequestID?.uuidString ?? "none"
            Self.trace("completeTerminationRequest ignored requestID=\(requestID.uuidString) pendingRequestID=\(pendingID)")
            return
        }

        let replies = pendingTerminationReplies
        let shouldDispatchAppTerminate = shouldTerminate && replies.isEmpty && shouldTerminateApplicationOnCompletion
        pendingTerminationRequestID = nil
        pendingTerminationReplies.removeAll()
        shouldTerminateApplicationOnCompletion = false
        Self.trace("completeTerminationRequest replying requestID=\(requestID.uuidString) shouldTerminate=\(shouldTerminate) replyCount=\(replies.count)")
        for reply in replies {
            reply(shouldTerminate)
        }

        if shouldDispatchAppTerminate {
            allowImmediateApplicationTermination = true
            Self.trace("completeTerminationRequest dispatching NSApp.terminate(nil) requestID=\(requestID.uuidString)")
            NSApp.terminate(nil)
        }
    }
}

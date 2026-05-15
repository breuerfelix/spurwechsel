import ComposableArchitecture
import Foundation
import os

@MainActor
final class EditorRuntime {
    static let maxWarmRuntimes = 6
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "dev.breuer.spurwechsel",
        category: "VSCodeDebug"
    )
    private static func trace(_ message: String) {
        #if DEBUG
        print("[VSCodeDebug][EditorRuntime] \(message)")
        #else
        logger.debug("\(message, privacy: .public)")
        #endif
    }

    enum BrowserEvent: Equatable {
        case navigationStarted(workspaceID: String)
        case navigationCommitted(workspaceID: String)
        case navigationFinished(workspaceID: String)
        case navigationFailed(workspaceID: String, message: String)
    }

    enum BrowserLoadResult: Equatable {
        case startedNavigation
        case alreadyRequestedPage(isLoading: Bool)
        case runtimeUnavailable
    }

    private let vscodeServerRuntime: VSCodeServerRuntime
    private var webRuntimesByWorkspaceID: [String: EmbeddedWebViewRuntime] = [:]
    private var mountedWorkspaceIDs: [String] = []
    private var runtimeEventContinuation: AsyncThrowingStream<VSCodeServerRuntime.Event, Error>.Continuation?
    private var browserEventContinuation: AsyncStream<BrowserEvent>.Continuation?

    init() {
        self.vscodeServerRuntime = VSCodeServerRuntime()
    }

    init(vscodeServerRuntime: VSCodeServerRuntime) {
        self.vscodeServerRuntime = vscodeServerRuntime
    }

    func startStream(
        workspaceID: String,
        workspacePath: String,
        port: Int
    ) -> AsyncThrowingStream<VSCodeServerRuntime.Event, Error> {
        Self.trace("startStream workspaceID=\(workspaceID) path=\(workspacePath) port=\(port)")
        runtimeEventContinuation?.finish()
        return AsyncThrowingStream { continuation in
            runtimeEventContinuation = continuation
            vscodeServerRuntime.onEvent = { [weak self] event in
                Task { @MainActor [weak self] in
                    Self.trace("runtimeEvent workspaceID=\(workspaceID) event=\(String(describing: event))")
                    self?.runtimeEventContinuation?.yield(event)
                }
            }
            vscodeServerRuntime.start(
                workspaceID: workspaceID,
                workspacePath: workspacePath,
                port: port
            )
            continuation.onTermination = { @Sendable _ in
                Task { @MainActor [weak self] in
                    Self.trace("startStream terminated workspaceID=\(workspaceID)")
                    self?.runtimeEventContinuation = nil
                    self?.vscodeServerRuntime.onEvent = nil
                }
            }
        }
    }

    func stop() {
        vscodeServerRuntime.stop()
    }

    func shutdown(
        graceTimeout: TimeInterval,
        forceKillTimeout: TimeInterval
    ) async -> VSCodeServerShutdownSummary {
        await vscodeServerRuntime.shutdown(
            graceTimeout: graceTimeout,
            forceKillTimeout: forceKillTimeout
        )
    }

    func browserEvents() -> AsyncStream<BrowserEvent> {
        AsyncStream { continuation in
            browserEventContinuation = continuation
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.browserEventContinuation = nil
                }
            }
        }
    }

    func prepareWebRuntime(forWorkspaceID workspaceID: String) {
        guard webRuntimesByWorkspaceID[workspaceID] == nil else {
            Self.trace("prepareWebRuntime reuse workspaceID=\(workspaceID)")
            touchMountedWorkspace(workspaceID)
            return
        }

        Self.trace("prepareWebRuntime create workspaceID=\(workspaceID)")
        let runtime = EmbeddedWebViewRuntime()
        runtime.handlers.onNavigationStarted = { [weak self] _ in
            Task { @MainActor [weak self] in
                Self.trace("browserEvent navigationStarted workspaceID=\(workspaceID)")
                self?.browserEventContinuation?.yield(.navigationStarted(workspaceID: workspaceID))
            }
        }
        runtime.handlers.onNavigationCommitted = { [weak self] _ in
            Task { @MainActor [weak self] in
                Self.trace("browserEvent navigationCommitted workspaceID=\(workspaceID)")
                self?.browserEventContinuation?.yield(.navigationCommitted(workspaceID: workspaceID))
            }
        }
        runtime.handlers.onNavigationFinished = { [weak self] _ in
            Task { @MainActor [weak self] in
                Self.trace("browserEvent navigationFinished workspaceID=\(workspaceID)")
                self?.browserEventContinuation?.yield(.navigationFinished(workspaceID: workspaceID))
            }
        }
        runtime.handlers.onNavigationFailed = { [weak self] _, message in
            Task { @MainActor [weak self] in
                Self.trace("browserEvent navigationFailed workspaceID=\(workspaceID) message=\(message)")
                self?.browserEventContinuation?.yield(.navigationFailed(
                    workspaceID: workspaceID,
                    message: message
                ))
            }
        }
        webRuntimesByWorkspaceID[workspaceID] = runtime
        touchMountedWorkspace(workspaceID)
        evictStaleWebRuntimesIfNeeded()
    }

    func webRuntimeIfPrepared(forWorkspaceID workspaceID: String) -> EmbeddedWebViewRuntime? {
        if let runtime = webRuntimesByWorkspaceID[workspaceID] {
            touchMountedWorkspace(workspaceID)
            return runtime
        }
        return nil
    }

    func loadWorkspaceInBrowser(
        workspaceID: String,
        workspacePath: String,
        serverURL: URL
    ) -> BrowserLoadResult {
        Self.trace("loadWorkspaceInBrowser enter workspaceID=\(workspaceID) path=\(workspacePath) serverURL=\(serverURL.absoluteString)")
        guard let workspaceURL = codeServerFolderURL(
            serverURL: serverURL,
            workspacePath: workspacePath
        ) else {
            Self.trace("loadWorkspaceInBrowser runtimeUnavailable invalidURL workspaceID=\(workspaceID)")
            return .runtimeUnavailable
        }

        prepareWebRuntime(forWorkspaceID: workspaceID)
        guard let runtime = webRuntimeIfPrepared(forWorkspaceID: workspaceID) else {
            Self.trace("loadWorkspaceInBrowser runtimeUnavailable missingRuntime workspaceID=\(workspaceID)")
            return .runtimeUnavailable
        }

        if runtime.loadIfNeeded(workspaceURL) {
            Self.trace("loadWorkspaceInBrowser startedNavigation workspaceID=\(workspaceID) workspaceURL=\(workspaceURL.absoluteString)")
            return .startedNavigation
        }

        switch runtime.requestedAddressState(for: workspaceURL.absoluteString) {
        case .loadingRequestedAddress:
            Self.trace("loadWorkspaceInBrowser alreadyRequested loading workspaceID=\(workspaceID) workspaceURL=\(workspaceURL.absoluteString)")
            return .alreadyRequestedPage(isLoading: true)
        case .showingRequestedAddress:
            Self.trace("loadWorkspaceInBrowser alreadyRequested ready workspaceID=\(workspaceID) workspaceURL=\(workspaceURL.absoluteString)")
            return .alreadyRequestedPage(isLoading: false)
        case .notShowingRequestedAddress:
            Self.trace("loadWorkspaceInBrowser staleAddress retry workspaceID=\(workspaceID) workspaceURL=\(workspaceURL.absoluteString)")
            runtime.invalidateLastRequestedAddress()
            if runtime.loadIfNeeded(workspaceURL) {
                Self.trace("loadWorkspaceInBrowser retry startedNavigation workspaceID=\(workspaceID)")
                return .startedNavigation
            }
            Self.trace("loadWorkspaceInBrowser retry noNavigation fallbackLoading workspaceID=\(workspaceID)")
            return .alreadyRequestedPage(isLoading: true)
        }
    }

    func invalidateBrowserAddresses() {
        for runtime in webRuntimesByWorkspaceID.values {
            runtime.invalidateLastRequestedAddress()
        }
    }

    func removeBrowserRuntime(forWorkspaceID workspaceID: String) {
        if let runtime = webRuntimesByWorkspaceID.removeValue(forKey: workspaceID) {
            runtime.resetToBlank()
        }
        mountedWorkspaceIDs.removeAll { $0 == workspaceID }
    }

    func syncBrowserRuntimeCache(keepingWorkspaceIDs: Set<String>) {
        let staleWorkspaceIDs = Set(webRuntimesByWorkspaceID.keys).subtracting(keepingWorkspaceIDs)
        for workspaceID in staleWorkspaceIDs {
            removeBrowserRuntime(forWorkspaceID: workspaceID)
        }
        mountedWorkspaceIDs = mountedWorkspaceIDs.filter { keepingWorkspaceIDs.contains($0) }
    }

    private func touchMountedWorkspace(_ workspaceID: String) {
        mountedWorkspaceIDs.removeAll { $0 == workspaceID }
        mountedWorkspaceIDs.append(workspaceID)
    }

    private func evictStaleWebRuntimesIfNeeded() {
        while mountedWorkspaceIDs.count > Self.maxWarmRuntimes {
            guard let oldestWorkspaceID = mountedWorkspaceIDs.first else {
                return
            }
            removeBrowserRuntime(forWorkspaceID: oldestWorkspaceID)
        }
    }

    private func codeServerFolderURL(
        serverURL: URL,
        workspacePath: String
    ) -> URL? {
        guard var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = "/"
        components.queryItems = [
            URLQueryItem(name: "folder", value: workspacePath)
        ]
        return components.url
    }
}

import ComposableArchitecture
import Foundation
import os

struct LifecycleFeature: Reducer {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "dev.breuer.spurwechsel",
        category: "LifecycleFeature"
    )
    private static func trace(_ message: String) {
        #if DEBUG
        print("[LifecycleFeature] \(message)")
        #else
        logger.debug("\(message, privacy: .public)")
        #endif
    }

    @Dependency(\.appLifecycleBridgeClient) var appLifecycleBridgeClient
    @Dependency(\.terminalRegistryClient) var terminalRegistryClient
    @Dependency(\.vscodeRuntimeClient) var vscodeRuntimeClient
    @Dependency(\.windowClient) var windowClient

    struct ShutdownPresentationState: Equatable {
        var isVisible = false
        var statusMessage = "Shutting everything down…"
        var detailMessage = "Closing terminals, agents, and background sessions."
    }

    @ObservableState
    struct State: Equatable {
        var appIsActive = true
        var hasLaunched = false
        var lastTerminationSummary: AppTerminationSummary?
        var pendingExternalURLs: [URL] = []
        var pendingTerminationRequestID: UUID?
        var shutdownPresentation = ShutdownPresentationState()
        var terminationInProgress = false
        var windowIsKey = true

        var terminalSurfacesAreForeground: Bool {
            appIsActive && windowIsKey
        }
    }

    enum Delegate: Equatable {
        case appLaunched
        case externalOpenRequested(ExternalWorkspaceDeepLinkRequest)
        case externalOpenFailed(detailMessage: String)
    }

    enum Action {
        case enqueueExternalURLs([URL])
        case clearExternalURLs
        case appDidFinishLaunching
        case startWindowObservation
        case openURLs([URL])
        case drainExternalURLs
        case setApplicationActive(Bool)
        case setWindowKey(Bool)
        case terminationRequested(UUID)
        case terminationFinished(UUID, AppTerminationSummary)
        case setTerminationInProgress(Bool)
        case delegate(Delegate)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .appDidFinishLaunching:
                state.hasLaunched = true
                return .concatenate(
                    .send(.startWindowObservation),
                    .send(.delegate(.appLaunched)),
                    state.pendingExternalURLs.isEmpty ? .none : .send(.drainExternalURLs)
                )
            case .startWindowObservation:
                return .merge(
                    .run { send in
                        let stream = await windowClient.appActiveStream()
                        for await isActive in stream {
                            await send(.setApplicationActive(isActive))
                        }
                    },
                    .run { send in
                        let stream = await windowClient.windowKeyStream()
                        for await isKey in stream {
                            await send(.setWindowKey(isKey))
                        }
                    }
                )

            case let .openURLs(urls):
                state.pendingExternalURLs.append(contentsOf: urls)
                guard state.hasLaunched else {
                    return .none
                }
                return .send(.drainExternalURLs)

            case let .setApplicationActive(isActive):
                state.appIsActive = isActive

            case let .setWindowKey(isKey):
                state.windowIsKey = isKey

            case .drainExternalURLs:
                guard !state.pendingExternalURLs.isEmpty else {
                    return .none
                }

                let urls = state.pendingExternalURLs
                state.pendingExternalURLs.removeAll()

                let effects = urls.map { url -> Effect<Action> in
                    do {
                        return .send(.delegate(.externalOpenRequested(try ExternalWorkspaceDeepLinkRequest(url: url))))
                    } catch {
                        return .send(.delegate(.externalOpenFailed(detailMessage: error.localizedDescription)))
                    }
                }
                return .concatenate(effects)

            case let .terminationRequested(requestID):
                guard !state.terminationInProgress else {
                    Self.trace("terminationRequested ignored requestID=\(requestID.uuidString) alreadyInProgress=true")
                    return .none
                }

                Self.trace("terminationRequested begin requestID=\(requestID.uuidString)")
                state.pendingTerminationRequestID = requestID
                state.lastTerminationSummary = nil
                state.terminationInProgress = true
                state.shutdownPresentation = ShutdownPresentationState(
                    isVisible: true,
                    statusMessage: "Shutting everything down…",
                    detailMessage: "Closing terminals, agents, and background sessions."
                )

                return .run { @MainActor send in
                    let graceTimeout = AppRuntime.shutdownGraceTimeout
                    let forceKillTimeout = AppRuntime.shutdownForceKillTimeout
                    Self.trace("shutdown terminal start requestID=\(requestID.uuidString)")
                    async let terminalSummary = terminalRegistryClient.shutdownAll(
                        graceTimeout,
                        forceKillTimeout
                    )
                    Self.trace("shutdown vscode start requestID=\(requestID.uuidString)")
                    async let serverSummary = vscodeRuntimeClient.shutdown(
                        graceTimeout,
                        forceKillTimeout
                    )

                    let (terminalSummaryValue, serverSummaryValue) = await (terminalSummary, serverSummary)
                    Self.trace(
                        "shutdown terminal done requestID=\(requestID.uuidString) sessions=\(terminalSummaryValue.sessionCount) forced=\(terminalSummaryValue.forcedKillCount) timedOut=\(terminalSummaryValue.timedOutCount)"
                    )
                    Self.trace(
                        "shutdown vscode done requestID=\(requestID.uuidString) forced=\(serverSummaryValue.didForceKill) timedOut=\(serverSummaryValue.didTimeout)"
                    )

                    let summary = AppTerminationSummary(
                        forcedKillCount: terminalSummaryValue.forcedKillCount + (serverSummaryValue.didForceKill ? 1 : 0),
                        timedOutCount: terminalSummaryValue.timedOutCount + (serverSummaryValue.didTimeout ? 1 : 0)
                    )
                    Self.trace(
                        "terminationRequested completed requestID=\(requestID.uuidString) forced=\(summary.forcedKillCount) timedOut=\(summary.timedOutCount)"
                    )
                    await send(.terminationFinished(requestID, summary))
                }

            case let .terminationFinished(requestID, summary):
                Self.trace(
                    "terminationFinished requestID=\(requestID.uuidString) forced=\(summary.forcedKillCount) timedOut=\(summary.timedOutCount)"
                )
                state.pendingTerminationRequestID = nil
                state.lastTerminationSummary = summary
                state.terminationInProgress = false

                if summary.timedOutCount > 0 {
                    state.shutdownPresentation.statusMessage = "Forcing final shutdown…"
                    state.shutdownPresentation.detailMessage = "Force-closed \(summary.forcedKillCount) session(s). \(summary.timedOutCount) did not confirm exit."
                } else if summary.forcedKillCount > 0 {
                    state.shutdownPresentation.statusMessage = "Finalizing shutdown…"
                    state.shutdownPresentation.detailMessage = "Force-closed \(summary.forcedKillCount) unresponsive session(s)."
                } else {
                    state.shutdownPresentation.statusMessage = "Finalizing shutdown…"
                    state.shutdownPresentation.detailMessage = "All managed sessions closed cleanly."
                }

                return .run { @MainActor _ in
                    Self.trace("terminationFinished replying requestID=\(requestID.uuidString)")
                    appLifecycleBridgeClient.completeTerminationRequest(requestID, true)
                }

            case let .enqueueExternalURLs(urls):
                state.pendingExternalURLs.append(contentsOf: urls)
            case .clearExternalURLs:
                state.pendingExternalURLs.removeAll()
            case let .setTerminationInProgress(inProgress):
                state.terminationInProgress = inProgress
            case .delegate:
                return .none
            }
            return .none
        }
    }
}

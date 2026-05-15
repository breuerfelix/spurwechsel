import ComposableArchitecture
import Foundation

struct LifecycleFeature: Reducer {
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
                    return .none
                }

                state.pendingTerminationRequestID = requestID
                state.lastTerminationSummary = nil
                state.terminationInProgress = true
                state.shutdownPresentation = ShutdownPresentationState(
                    isVisible: true,
                    statusMessage: "Shutting everything down…",
                    detailMessage: "Closing terminals, agents, and background sessions."
                )

                return .run { send in
                    async let terminalSummary = terminalRegistryClient.shutdownAll(
                        AppRuntime.shutdownGraceTimeout,
                        AppRuntime.shutdownForceKillTimeout
                    )
                    async let serverSummary = vscodeRuntimeClient.shutdown(
                        AppRuntime.shutdownGraceTimeout,
                        AppRuntime.shutdownForceKillTimeout
                    )
                    let (terminalSummaryValue, serverSummaryValue) = await (terminalSummary, serverSummary)

                    let summary = AppTerminationSummary(
                        forcedKillCount: terminalSummaryValue.forcedKillCount + (serverSummaryValue.didForceKill ? 1 : 0),
                        timedOutCount: terminalSummaryValue.timedOutCount + (serverSummaryValue.didTimeout ? 1 : 0)
                    )
                    await send(.terminationFinished(requestID, summary))
                }

            case let .terminationFinished(requestID, summary):
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

                return .run { _ in
                    await appLifecycleBridgeClient.completeTerminationRequest(requestID, true)
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

import ComposableArchitecture
import Foundation
import os

private let editorFeatureLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "dev.breuer.spurwechsel",
    category: "VSCodeDebug"
)

private func editorTrace(_ message: String) {
    #if DEBUG
    print("[VSCodeDebug][EditorFeature] \(message)")
    #else
    editorFeatureLogger.debug("\(message, privacy: .public)")
    #endif
}

struct EditorFeature: Reducer {
    @Dependency(\.configClient) var configClient
    @Dependency(\.vscodeRuntimeClient) var vscodeRuntimeClient

    @ObservableState
    struct State: Equatable {
        var sessionsByWorkspaceID: [String: EditorSessionState]
        var selectedWorkspaceID: String?
        var vscodeMountedWorkspaceIDs: [String]
        var isObservingBrowserEvents = false

        mutating func prepareVSCodeSelection(
            _ selection: WorkspaceSelection,
            projects: ProjectsState
        ) {
            let workspaceID = selection.stableID
            selectedWorkspaceID = workspaceID

            let workspaceName = projects.node(for: selection)?.title
            let workspacePath = projects.path(for: selection)
            editorTrace("prepareVSCodeSelection workspaceID=\(workspaceID) workspaceName=\(workspaceName ?? "nil") workspacePath=\(workspacePath ?? "nil")")

            updateSession(workspaceID: workspaceID) { session in
                session.workspaceSelectionID = workspaceID
                session.workspaceName = workspaceName
                session.workspacePath = workspacePath

                if workspacePath == nil {
                    session.serverAddress = nil
                    session.workspaceAddress = nil
                    session.status = .missingWorkspace
                    session.statusMessage = "Select project or worktree before starting code-server."
                    session.errorMessage = "No workspace path available for VSCode view."
                    session.lastOutputLine = nil
                    session.browserPhase = .idle
                } else if session.status == .missingWorkspace {
                    session.status = .idle
                    session.statusMessage = "Select VSCode view to start code-server."
                    session.errorMessage = nil
                    session.lastOutputLine = nil
                    session.browserPhase = .idle
                }
            }
        }

        mutating func handleRuntimeEvent(
            workspaceID: String,
            _ event: VSCodeServerRuntime.Event
        ) {
            editorTrace("handleRuntimeEvent workspaceID=\(workspaceID) event=\(String(describing: event))")
            switch event {
            case let .starting(_, workspacePath, serverURL):
                selectedWorkspaceID = workspaceID
                touchMountedWorkspace(workspaceID)
                updateSession(workspaceID: workspaceID) { session in
                    session.workspaceSelectionID = workspaceID
                    session.workspacePath = workspacePath
                    let displayName = session.workspaceName ?? "selected workspace"
                    session.status = .starting
                    session.statusMessage = "Starting code-server for \(displayName) at \(serverURL.host ?? "127.0.0.1"):\(serverURL.port ?? 0)…"
                    session.errorMessage = nil
                    session.lastOutputLine = nil
                    session.serverAddress = serverURL.absoluteString
                    session.workspaceAddress = nil
                    session.browserPhase = .loading
                }
            case let .outputLine(line):
                updateSession(workspaceID: workspaceID) { session in
                    session.lastOutputLine = line
                }
            case let .authRequired(line):
                updateSession(workspaceID: workspaceID) { session in
                    session.status = .authRequired
                    session.statusMessage = "Authentication needed for code-server. Resolve auth, then re-enter VSCode view."
                    session.errorMessage = line
                    session.lastOutputLine = line
                    session.browserPhase = .loading
                }
            case let .serverReady(url):
                touchMountedWorkspace(workspaceID)
                let workspacePath = sessionsByWorkspaceID[workspaceID]?.workspacePath
                let workspaceAddress = codeServerFolderURL(
                    serverURL: url,
                    workspacePath: workspacePath
                )?.absoluteString
                updateSession(workspaceID: workspaceID) { session in
                    session.serverAddress = url.absoluteString
                    session.workspaceAddress = workspaceAddress
                    session.status = .running
                    if let workspaceName = session.workspaceName {
                        session.statusMessage = "code-server active for \(workspaceName) at \(url.absoluteString)."
                    } else {
                        session.statusMessage = "code-server active at \(url.absoluteString)."
                    }
                    session.errorMessage = nil
                    if session.browserPhase == .idle {
                        session.browserPhase = .loading
                    }
                }
            case .stopped:
                markAllSessionsStopped()
            case let .failed(reason, message, lastOutputLine):
                markAllSessionsFailed(
                    reason: reason,
                    message: message,
                    lastOutputLine: lastOutputLine
                )
            }
        }

        mutating func handleWebNavigationStarted(workspaceID: String) {
            updateSession(workspaceID: workspaceID) { session in
                editorTrace("webNavigationStarted workspaceID=\(workspaceID) status=\(String(describing: session.status)) phase=\(String(describing: session.browserPhase))")
                session.browserPhase = .loading
            }
        }

        mutating func handleWebNavigationReady(workspaceID: String) {
            updateSession(workspaceID: workspaceID) { session in
                guard session.status == .running else {
                    editorTrace("webNavigationReady ignored workspaceID=\(workspaceID) status=\(String(describing: session.status))")
                    return
                }
                session.browserPhase = .ready
                editorTrace("webNavigationReady workspaceID=\(workspaceID) phase=ready")
                if session.errorMessage?.hasPrefix("code-server page failed to load:") == true {
                    session.errorMessage = nil
                }
            }
        }

        mutating func handleBrowserLoadAttempted(
            workspaceID: String,
            result: EditorRuntime.BrowserLoadResult
        ) {
            updateSession(workspaceID: workspaceID) { session in
                guard session.status == .running else {
                    editorTrace("browserLoadAttempted ignored workspaceID=\(workspaceID) status=\(String(describing: session.status)) result=\(String(describing: result))")
                    return
                }

                if case .failed = session.browserPhase {
                    editorTrace("browserLoadAttempted ignoredFailed workspaceID=\(workspaceID) result=\(String(describing: result))")
                    return
                }

                switch result {
                case .startedNavigation:
                    session.browserPhase = .loading
                    editorTrace("browserLoadAttempted startedNavigation workspaceID=\(workspaceID) phase=loading")
                case let .alreadyRequestedPage(isLoading):
                    session.browserPhase = isLoading ? .loading : .ready
                    editorTrace("browserLoadAttempted alreadyRequested workspaceID=\(workspaceID) isLoading=\(isLoading) phase=\(String(describing: session.browserPhase))")
                case .runtimeUnavailable:
                    session.errorMessage = "VSCode browser runtime is unavailable."
                    session.statusMessage = "code-server running, but embedded browser is unavailable."
                    session.browserPhase = .failed("browser runtime unavailable")
                    editorTrace("browserLoadAttempted runtimeUnavailable workspaceID=\(workspaceID) phase=failed")
                }
            }
        }

        mutating func handleWebNavigationFailed(
            workspaceID: String,
            message: String
        ) {
            updateSession(workspaceID: workspaceID) { session in
                guard session.status == .running else {
                    editorTrace("webNavigationFailed ignored workspaceID=\(workspaceID) status=\(String(describing: session.status))")
                    return
                }
                session.errorMessage = "code-server page failed to load: \(message)"
                session.statusMessage = "code-server running, but browser load failed."
                session.browserPhase = .failed(message)
                editorTrace("webNavigationFailed workspaceID=\(workspaceID) message=\(message)")
            }
        }

        mutating func pruneWorkspaces(
            keepingWorkspaceIDs: Set<String>,
            fallbackSelectedWorkspaceID: String?
        ) {
            sessionsByWorkspaceID = sessionsByWorkspaceID.filter { key, _ in
                keepingWorkspaceIDs.contains(key)
            }
            vscodeMountedWorkspaceIDs = vscodeMountedWorkspaceIDs.filter {
                keepingWorkspaceIDs.contains($0)
            }

            if let selectedWorkspaceID,
               !keepingWorkspaceIDs.contains(selectedWorkspaceID) {
                self.selectedWorkspaceID = nil
            }

            if self.selectedWorkspaceID == nil,
               let fallbackSelectedWorkspaceID,
               keepingWorkspaceIDs.contains(fallbackSelectedWorkspaceID) {
                self.selectedWorkspaceID = fallbackSelectedWorkspaceID
            }
        }

        func visibleSession() -> (workspaceID: String, session: EditorSessionState)? {
            guard let workspaceID = selectedWorkspaceID,
                  let session = sessionsByWorkspaceID[workspaceID]
            else {
                return nil
            }
            return (workspaceID, session)
        }

        func sharedServerSession() -> EditorSessionState? {
            let activeStatuses: Set<VSCodeServerStatus> = [.starting, .running, .authRequired, .stopping]
            return sessionsByWorkspaceID.values.first { session in
                activeStatuses.contains(session.status) && session.serverAddress != nil
            }
        }

        mutating func touchMountedWorkspace(_ workspaceID: String) {
            vscodeMountedWorkspaceIDs.removeAll { $0 == workspaceID }
            vscodeMountedWorkspaceIDs.append(workspaceID)
            while vscodeMountedWorkspaceIDs.count > EditorRuntime.maxWarmRuntimes {
                vscodeMountedWorkspaceIDs.removeFirst()
            }
        }

        mutating func markAllSessionsStopped() {
            for workspaceID in sessionsByWorkspaceID.keys {
                updateSession(workspaceID: workspaceID) { session in
                    guard session.status != .missingWorkspace else {
                        return
                    }
                    session.status = .stopped
                    session.serverAddress = nil
                    session.workspaceAddress = nil
                    session.statusMessage = "code-server stopped. Re-enter VSCode view to restart."
                    session.errorMessage = nil
                    session.lastOutputLine = nil
                    session.browserPhase = .idle
                }
            }
        }

        mutating func markAllSessionsFailed(
            reason: VSCodeServerRuntime.FailureReason,
            message: String,
            lastOutputLine: String?
        ) {
            for workspaceID in sessionsByWorkspaceID.keys {
                updateSession(workspaceID: workspaceID) { session in
                    switch reason {
                    case .cliMissing:
                        session.status = .cliMissing
                    case .portInUse:
                        session.status = .portInUse
                    case .startupFailed:
                        session.status = .startupFailed
                    case .authRequired:
                        session.status = .authRequired
                    case .urlNotFound:
                        session.status = .urlNotFound
                    }
                    session.statusMessage = message
                    session.errorMessage = message
                    session.lastOutputLine = lastOutputLine
                    session.serverAddress = nil
                    session.workspaceAddress = nil
                    session.browserPhase = .failed(message)
                }
            }
        }

        private mutating func updateSession(
            workspaceID: String,
            _ update: (inout EditorSessionState) -> Void
        ) {
            var session = sessionsByWorkspaceID[workspaceID] ?? EditorSessionState(
                workspaceSelectionID: workspaceID,
                workspaceName: nil,
                workspacePath: nil,
                serverAddress: nil,
                workspaceAddress: nil,
                status: .idle,
                statusMessage: "Select VSCode view to start code-server.",
                errorMessage: nil,
                lastOutputLine: nil,
                browserPhase: .idle
            )
            update(&session)
            sessionsByWorkspaceID[workspaceID] = session
        }

        private func codeServerFolderURL(
            serverURL: URL,
            workspacePath: String?
        ) -> URL? {
            guard let workspacePath,
                  var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false)
            else {
                return nil
            }
            components.path = "/"
            components.queryItems = [
                URLQueryItem(name: "folder", value: workspacePath)
            ]
            return components.url
        }
    }

    enum Action {
        case startBrowserEventObservation
        case runtimeEvent(workspaceID: String, event: VSCodeServerRuntime.Event)
        case browserLoadAttempted(workspaceID: String, result: EditorRuntime.BrowserLoadResult)
        case syncVisibleWorkspace(forceRestart: Bool)
        case pruneWorkspaces(keepingWorkspaceIDs: [String], fallbackSelectedWorkspaceID: String?)
        case workspacesRemoved([String])
        case setSession(workspaceID: String, session: EditorSessionState)
        case setSelectedWorkspaceID(String?)
        case setMountedWorkspaceIDs([String])
        case webNavigationStarted(workspaceID: String)
        case webNavigationCommitted(workspaceID: String)
        case webNavigationFinished(workspaceID: String)
        case webNavigationFailed(workspaceID: String, message: String)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .startBrowserEventObservation:
                guard !state.isObservingBrowserEvents else {
                    editorTrace("startBrowserEventObservation ignored alreadyObserving=true")
                    return .none
                }
                state.isObservingBrowserEvents = true
                editorTrace("startBrowserEventObservation start")
                return .run { send in
                    let events = await vscodeRuntimeClient.browserEvents()
                    for await event in events {
                        switch event {
                        case let .navigationStarted(workspaceID):
                            await send(.webNavigationStarted(workspaceID: workspaceID))
                        case let .navigationCommitted(workspaceID):
                            await send(.webNavigationCommitted(workspaceID: workspaceID))
                        case let .navigationFinished(workspaceID):
                            await send(.webNavigationFinished(workspaceID: workspaceID))
                        case let .navigationFailed(workspaceID, message):
                            await send(.webNavigationFailed(workspaceID: workspaceID, message: message))
                        }
                    }
                }
            case let .runtimeEvent(workspaceID, event):
                state.handleRuntimeEvent(workspaceID: workspaceID, event)
                switch event {
                case let .serverReady(serverURL):
                    editorTrace("runtimeEvent serverReady workspaceID=\(workspaceID) selectedWorkspaceID=\(state.selectedWorkspaceID ?? "nil") serverURL=\(serverURL.absoluteString)")
                    let preferredWorkspaceID = state.selectedWorkspaceID ?? workspaceID
                    let targetWorkspaceID: String
                    let targetWorkspacePath: String

                    if let preferredSession = state.sessionsByWorkspaceID[preferredWorkspaceID],
                       let preferredWorkspacePath = preferredSession.workspacePath {
                        targetWorkspaceID = preferredWorkspaceID
                        targetWorkspacePath = preferredWorkspacePath
                    } else if let eventSession = state.sessionsByWorkspaceID[workspaceID],
                              let eventWorkspacePath = eventSession.workspacePath {
                        targetWorkspaceID = workspaceID
                        targetWorkspacePath = eventWorkspacePath
                    } else {
                        editorTrace("runtimeEvent serverReady noTargetWorkspace workspaceID=\(workspaceID)")
                        return .none
                    }

                    return .run { send in
                        let result = await vscodeRuntimeClient.loadWorkspaceInBrowser(
                            targetWorkspaceID,
                            targetWorkspacePath,
                            serverURL
                        )
                        await send(.browserLoadAttempted(
                            workspaceID: targetWorkspaceID,
                            result: result
                        ))
                    }
                case .stopped, .failed:
                    return .run { _ in
                        await vscodeRuntimeClient.invalidateBrowserAddresses()
                    }
                default:
                    return .none
                }
            case let .browserLoadAttempted(workspaceID, result):
                editorTrace("action browserLoadAttempted workspaceID=\(workspaceID) result=\(String(describing: result))")
                state.handleBrowserLoadAttempted(
                    workspaceID: workspaceID,
                    result: result
                )
                return .none
            case let .syncVisibleWorkspace(forceRestart):
                guard let (workspaceID, existingSession) = state.visibleSession() else {
                    editorTrace("syncVisibleWorkspace noVisibleSession forceRestart=\(forceRestart)")
                    return .none
                }
                editorTrace("syncVisibleWorkspace workspaceID=\(workspaceID) forceRestart=\(forceRestart) status=\(String(describing: existingSession.status)) phase=\(String(describing: existingSession.browserPhase)) path=\(existingSession.workspacePath ?? "nil")")

                guard let workspacePath = existingSession.workspacePath else {
                    var session = existingSession
                    session.serverAddress = nil
                    session.workspaceAddress = nil
                    session.status = .missingWorkspace
                    session.statusMessage = "Select project or worktree before starting code-server."
                    session.errorMessage = "No workspace path available for VSCode view."
                    session.lastOutputLine = nil
                    state.sessionsByWorkspaceID[workspaceID] = session

                    return .merge(
                        .run { _ in
                            await vscodeRuntimeClient.stop()
                        },
                        .run { _ in
                            await vscodeRuntimeClient.invalidateBrowserAddresses()
                        }
                    )
                }

                vscodeRuntimeClient.prepareWebRuntime(workspaceID)
                state.touchMountedWorkspace(workspaceID)

                var session = existingSession
                let activeStatuses: Set<VSCodeServerStatus> = [.starting, .running, .authRequired, .stopping]

                if !forceRestart, activeStatuses.contains(session.status) {
                    if session.status == .starting {
                        let address = session.serverAddress ?? session.workspaceAddress ?? "127.0.0.1"
                        let displayName = session.workspaceName ?? "selected workspace"
                        session.statusMessage = "Starting code-server for \(displayName) at \(address)…"
                        session.browserPhase = .loading
                        state.sessionsByWorkspaceID[workspaceID] = session
                        editorTrace("syncVisibleWorkspace keepStarting workspaceID=\(workspaceID) address=\(address)")
                        return .none
                    }

                    if session.status == .running,
                       let address = session.serverAddress,
                       let serverURL = URL(string: address) {
                        state.sessionsByWorkspaceID[workspaceID] = session
                        editorTrace("syncVisibleWorkspace reloadRunning workspaceID=\(workspaceID) serverURL=\(serverURL.absoluteString)")
                        return .run { send in
                            let result = await vscodeRuntimeClient.loadWorkspaceInBrowser(
                                workspaceID,
                                workspacePath,
                                serverURL
                            )
                            await send(.browserLoadAttempted(
                                workspaceID: workspaceID,
                                result: result
                            ))
                        }
                    }

                    state.sessionsByWorkspaceID[workspaceID] = session
                    editorTrace("syncVisibleWorkspace keepActiveNoReload workspaceID=\(workspaceID) status=\(String(describing: session.status))")
                    return .none
                }

                if !forceRestart,
                   let sharedSession = state.sharedServerSession(),
                   let sharedAddress = sharedSession.serverAddress,
                   let sharedServerURL = URL(string: sharedAddress) {
                    session.serverAddress = sharedAddress
                    session.workspaceAddress = nil
                    session.status = sharedSession.status
                    if sharedSession.status == .running {
                        session.statusMessage = "code-server active for \(session.workspaceName ?? "selected workspace") at \(sharedAddress)."
                    } else {
                        session.statusMessage = sharedSession.statusMessage
                    }
                    session.errorMessage = sharedSession.errorMessage
                    session.lastOutputLine = sharedSession.lastOutputLine
                    state.sessionsByWorkspaceID[workspaceID] = session

                    if sharedSession.status == .running {
                        editorTrace("syncVisibleWorkspace adoptSharedRunning workspaceID=\(workspaceID) sharedAddress=\(sharedAddress)")
                        return .run { send in
                            let result = await vscodeRuntimeClient.loadWorkspaceInBrowser(
                                workspaceID,
                                workspacePath,
                                sharedServerURL
                            )
                            await send(.browserLoadAttempted(
                                workspaceID: workspaceID,
                                result: result
                            ))
                        }
                    }

                    editorTrace("syncVisibleWorkspace adoptSharedNonRunning workspaceID=\(workspaceID) sharedStatus=\(String(describing: sharedSession.status))")
                    return .none
                }

                let displayName = session.workspaceName ?? "selected workspace"
                session.serverAddress = nil
                session.workspaceAddress = nil
                session.status = .starting
                session.statusMessage = "Starting code-server for \(displayName)…"
                session.errorMessage = nil
                session.lastOutputLine = nil
                session.browserPhase = .loading
                state.sessionsByWorkspaceID[workspaceID] = session
                editorTrace("syncVisibleWorkspace startingFresh workspaceID=\(workspaceID) displayName=\(displayName)")

                let startingSession = session
                return .run { @MainActor send in
                    do {
                        let loadResult = try await configClient.load()
                        vscodeRuntimeClient.invalidateBrowserAddresses()
                        let runtimeEvents = vscodeRuntimeClient.start(
                            workspaceID,
                            workspacePath,
                            loadResult.config.codeServer.resolvedPort
                        )
                        for try await runtimeEvent in runtimeEvents {
                            await send(.runtimeEvent(workspaceID: workspaceID, event: runtimeEvent))
                        }
                    } catch {
                        var failedSession = startingSession
                        failedSession.status = .startupFailed
                        failedSession.statusMessage = error.localizedDescription
                        failedSession.errorMessage = error.localizedDescription
                        await send(.setSession(workspaceID: workspaceID, session: failedSession))
                    }
                }
            case let .pruneWorkspaces(keepingWorkspaceIDs, fallbackSelectedWorkspaceID):
                state.pruneWorkspaces(
                    keepingWorkspaceIDs: Set(keepingWorkspaceIDs),
                    fallbackSelectedWorkspaceID: fallbackSelectedWorkspaceID
                )
                return .run { _ in
                    await vscodeRuntimeClient.syncBrowserRuntimeCache(Set(keepingWorkspaceIDs))
                }
            case let .workspacesRemoved(workspaceIDs):
                guard !workspaceIDs.isEmpty else {
                    return .none
                }
                let removedWorkspaceIDs = Set(workspaceIDs)
                let remainingWorkspaceIDs = Set(state.sessionsByWorkspaceID.keys).subtracting(removedWorkspaceIDs)
                state.pruneWorkspaces(
                    keepingWorkspaceIDs: remainingWorkspaceIDs,
                    fallbackSelectedWorkspaceID: state.selectedWorkspaceID
                )
                return .run { _ in
                    for workspaceID in workspaceIDs {
                        await vscodeRuntimeClient.removeBrowserRuntime(workspaceID)
                    }
                }
            case let .setSession(workspaceID, session):
                state.sessionsByWorkspaceID[workspaceID] = session
            case let .setSelectedWorkspaceID(workspaceID):
                state.selectedWorkspaceID = workspaceID
            case let .setMountedWorkspaceIDs(workspaceIDs):
                state.vscodeMountedWorkspaceIDs = workspaceIDs
            case let .webNavigationStarted(workspaceID):
                state.handleWebNavigationStarted(workspaceID: workspaceID)
            case let .webNavigationCommitted(workspaceID):
                state.handleWebNavigationReady(workspaceID: workspaceID)
            case let .webNavigationFinished(workspaceID):
                state.handleWebNavigationReady(workspaceID: workspaceID)
            case let .webNavigationFailed(workspaceID, message):
                state.handleWebNavigationFailed(workspaceID: workspaceID, message: message)
            }
            return .none
        }
    }
}

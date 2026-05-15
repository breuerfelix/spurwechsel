import ComposableArchitecture
import Foundation
import GhosttyTerminal

struct AgentLaunchRequest {
    var workspaceSelection: WorkspaceSelection
    var workingDirectory: String
    var agentName: String
    var command: String
    var terminalTheme: TerminalTheme
}

struct AgentFeature: Reducer {
    @Dependency(\.agentRuntimeClient) var agentRuntimeClient
    @Dependency(\.terminalRegistryClient) var terminalRegistryClient

    @ObservableState
    struct State: Equatable {
        var agents: AgentState
    }

    enum Delegate {
        case sessionLaunched(sessionID: UUID, workspaceSelection: WorkspaceSelection)
        case sessionsRemoved([UUID])
    }

    enum Action {
        case deleteSession(UUID)
        case delegate(Delegate)
        case handleDesktopNotification(sessionID: UUID, title: String, body: String)
        case insertSession(AgentSession, nextAgentCount: Int)
        case launchRequested(AgentLaunchRequest)
        case processTerminated(sessionID: UUID, exitCode: Int32?)
        case runtimeControllerReady(sessionID: UUID)
        case selectSession(UUID)
        case setAgents(AgentState)
        case updateTerminalTitle(sessionID: UUID, title: String)
        case workspacesRemoved(Set<WorkspaceSelection>)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .deleteSession(sessionID):
                guard state.agents.sessions.contains(where: { $0.id == sessionID }) else {
                    return .none
                }
                state.agents.removeSession(sessionID)
                return releaseControllersAndNotify(sessionIDs: [sessionID])
            case .delegate:
                return .none
            case let .handleDesktopNotification(sessionID, title, body):
                state.agents.handleDesktopNotification(
                    sessionID: sessionID,
                    title: title,
                    body: body
                )
                return .none
            case let .insertSession(session, nextAgentCount):
                state.agents.sessions.append(session)
                state.agents.selectedSessionID = session.id
                state.agents.nextAgentCount = nextAgentCount
                return .none
            case let .launchRequested(request):
                let agentKind = AgentKind.detect(from: request.command)
                let launchPlan = agentRuntimeClient.buildLaunchPlan(
                    request.agentName,
                    request.command,
                    request.workingDirectory,
                    agentKind
                )
                let expectsRichStatus = launchPlan.expectsRichStatus
                let initialStatus: AgentSessionStatus = expectsRichStatus ? .idle : .running
                let session = AgentSession(
                    workspaceSelection: request.workspaceSelection,
                    name: "\(request.agentName)-\(state.agents.nextAgentCount)",
                    kind: agentKind,
                    status: initialStatus,
                    launcherName: request.agentName,
                    launchCommand: request.command,
                    workingDirectory: request.workingDirectory,
                    terminalTitle: request.agentName,
                    lastActivity: "now",
                    exitCode: nil,
                    expectsRichStatus: expectsRichStatus
                )

                state.agents.sessions.append(session)
                state.agents.selectedSessionID = session.id
                state.agents.nextAgentCount += 1

                return .concatenate(
                    .send(.delegate(.sessionLaunched(
                        sessionID: session.id,
                        workspaceSelection: request.workspaceSelection
                    ))),
                    .run { send in
                        let eventStream = await agentRuntimeClient.start(
                            session.id,
                            request.workingDirectory,
                            request.terminalTheme,
                            launchPlan
                        )

                        for await event in eventStream {
                            switch event {
                            case .controllerReady:
                                await send(.runtimeControllerReady(sessionID: session.id))
                            case let .terminalTitleChanged(title):
                                await send(.updateTerminalTitle(sessionID: session.id, title: title))
                            case let .processTerminated(exitCode):
                                await send(.processTerminated(sessionID: session.id, exitCode: exitCode))
                            case let .desktopNotification(title, body):
                                await send(.handleDesktopNotification(
                                        sessionID: session.id,
                                        title: title,
                                        body: body
                                    ))
                            }
                        }
                    }
                )
            case let .processTerminated(sessionID, exitCode):
                guard state.agents.sessions.contains(where: { $0.id == sessionID }) else {
                    return .none
                }
                state.agents.updateExitCode(for: sessionID, exitCode: exitCode)
                state.agents.removeSession(sessionID)
                return releaseControllersAndNotify(sessionIDs: [sessionID])
            case let .runtimeControllerReady(sessionID):
                state.agents.markRuntimeReady(for: sessionID)
                return .none
            case let .selectSession(sessionID):
                state.agents.selectSession(sessionID)
                return .none
            case let .setAgents(agents):
                state.agents = agents
                return .none
            case let .updateTerminalTitle(sessionID, title):
                state.agents.updateTerminalTitle(for: sessionID, title: title)
                return .none
            case let .workspacesRemoved(selections):
                let removedSessionIDs = state.agents.removeSessions(in: selections)
                return releaseControllersAndNotify(sessionIDs: removedSessionIDs)
            }
        }
    }
}

private extension AgentFeature {
    func releaseControllersAndNotify(sessionIDs: [UUID]) -> Effect<Action> {
        guard !sessionIDs.isEmpty else {
            return .none
        }

        return .concatenate(
            .run { _ in
                for sessionID in sessionIDs {
                    await terminalRegistryClient.releaseAgentController(sessionID)
                }
            },
            .send(.delegate(.sessionsRemoved(sessionIDs)))
        )
    }
}

private extension AgentState {
    mutating func handleDesktopNotification(
        sessionID: UUID,
        title: String,
        body: String
    ) {
        guard let session = sessions.first(where: { $0.id == sessionID }) else {
            return
        }
        guard session.kind == .opencode, session.expectsRichStatus else {
            return
        }

        switch AgentRichStatusEvent.parseDesktopNotification(title: title, body: body) {
        case .wrongTitle:
            return
        case .invalidPayload:
            if let eventType = heuristicEventType(in: body) {
                applyRichStatusEvent(type: eventType, summary: nil, to: sessionID)
            }
        case let .parsed(event):
            guard event.agent == .opencode else {
                return
            }
            updateRichStatusMetadata(for: sessionID, pluginVersion: event.pluginVersion)
            applyRichStatusEvent(type: event.type, summary: event.summary, to: sessionID)
        }
    }

    private func heuristicEventType(in body: String) -> AgentRichStatusEventType? {
        if body.contains("\"event\":\"session_start\"") {
            return .sessionStart
        }
        if body.contains("\"event\":\"prompt_submit\"") {
            return .promptSubmit
        }
        if body.contains("\"event\":\"stop\"") {
            return .stop
        }
        if body.contains("\"event\":\"permission_request\"") {
            return .permissionRequest
        }
        if body.contains("\"event\":\"question_asked\"") {
            return .questionAsked
        }
        if body.contains("\"event\":\"permission_replied\"") {
            return .permissionReplied
        }
        if body.contains("\"event\":\"tool_complete\"") {
            return .toolComplete
        }
        if body.contains("\"event\":\"idle_prompt\"") {
            return .idlePrompt
        }
        return nil
    }

    private mutating func applyRichStatusEvent(
        type: AgentRichStatusEventType,
        summary: String?,
        to sessionID: UUID
    ) {
        switch type {
        case .sessionStart, .promptSubmit:
            updateStatus(for: sessionID, status: .running, detail: nil)
        case .permissionRequest:
            updateStatus(
                for: sessionID,
                status: .waitingApproval,
                detail: summary ?? "Waiting for approval"
            )
        case .questionAsked:
            updateStatus(
                for: sessionID,
                status: .waitingInput,
                detail: summary ?? "Waiting for input"
            )
        case .permissionReplied:
            guard let session = sessions.first(where: { $0.id == sessionID }) else {
                return
            }
            if session.status == .waitingApproval || session.status == .waitingInput {
                updateStatus(for: sessionID, status: .running, detail: nil)
            }
        case .toolComplete, .idlePrompt:
            return
        case .stop:
            updateStatus(for: sessionID, status: .idle, detail: nil)
        }
    }
}

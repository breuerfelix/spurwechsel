import ComposableArchitecture
import Foundation
import os

struct AppFeature: Reducer {
    @Dependency(\.configClient) var configClient
    @Dependency(\.importPanelClient) var importPanelClient
    @Dependency(\.appControlClient) var appControlClient
    @Dependency(\.layoutPersistenceClient) var layoutPersistenceClient
    @Dependency(\.terminalRegistryClient) var terminalRegistryClient
    @Dependency(\.voiceInputClient) var voiceInputClient

    @ObservableState
    struct State: Equatable {
        var shell: ShellFeature.State
        var workbench: WorkbenchFeature.State
        var workspace: WorkspaceFeature.State
        var agent: AgentFeature.State
        var editor: EditorFeature.State
        var commandPalette: CommandPaletteFeature.State
        var lifecycle: LifecycleFeature.State
        var voiceInput: VoiceInputState
    }

    struct VoiceInputState: Equatable {
        var activeSessionID: UUID?
        var hasInsertedText = false
    }

    @CasePathable
    enum Action {
        case appLaunched
        case commandPaletteOperationFailed(String)
        case invokeCommand(CommandID, projectContextID: UUID?, workspaceContext: WorkspaceSelection?)
        case requestApplicationQuit
        case shortcut(CommandID)
        case toggleVoiceInput
        case voiceInputEvent(VoiceInputEvent)
        case stopVoiceInput
        case shell(ShellFeature.Action)
        case workbench(WorkbenchFeature.Action)
        case workspace(WorkspaceFeature.Action)
        case agent(AgentFeature.Action)
        case editor(EditorFeature.Action)
        case commandPalette(CommandPaletteFeature.Action)
        case lifecycle(LifecycleFeature.Action)
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.shell, action: \.shell) {
            ShellFeature()
        }
        Scope(state: \.workbench, action: \.workbench) {
            WorkbenchFeature()
        }
        Scope(state: \.workspace, action: \.workspace) {
            WorkspaceFeature()
        }
        Scope(state: \.agent, action: \.agent) {
            AgentFeature()
        }
        Scope(state: \.editor, action: \.editor) {
            EditorFeature()
        }
        Scope(state: \.commandPalette, action: \.commandPalette) {
            CommandPaletteFeature()
        }
        Scope(state: \.lifecycle, action: \.lifecycle) {
            LifecycleFeature()
        }

        Reduce { state, action in
            switch action {
            case .appLaunched:
                if state.workbench.surfaceTabs.tabs.isEmpty {
                    state.workbench.initializeDefaultTabs(
                        layout: state.shell.layout,
                        projects: state.workspace.projects,
                        agents: state.agent.agents
                    )
                }
                syncWorkbenchState(&state)
                syncEditorState(&state)
                return .concatenate(
                    .send(.editor(.startBrowserEventObservation)),
                    .merge(
                        .send(.shell(.startWindowObservation)),
                        surfaceStateChangedEffects(&state),
                        .run { @MainActor send in
                            do {
                                let loadResult = try await configClient.load()
                                send(.shell(.setResolvedShortcuts(loadResult.config.resolvedShortcuts)))
                                send(.shell(.setTerminalConfig(loadResult.config.terminal)))
                                send(.shell(.setThemeSet(loadResult.config.theme)))
                                send(.shell(.updateConfigDiagnosticsNotification(
                                    configClient.diagnosticsMessage(
                                        loadResult.diagnostics,
                                        configClient.configURL()
                                    )
                                )))
                                await send(.workspace(.refreshRequested(
                                    preferredSelection: nil,
                                    revealSidebars: false,
                                    activateMainWindow: false,
                                    reportErrors: false
                                )))
                            } catch {
                                // Keep boot resilient: initial state still usable without config refresh.
                            }
                        }
                    )
                )
            case let .commandPaletteOperationFailed(message):
                return .send(.commandPalette(.setNotice(CommandBarNotice(text: message, isError: true))))
            case .requestApplicationQuit:
                return .run { _ in
                    await appControlClient.requestApplicationQuit()
                }
            case let .shortcut(command):
                switch command {
                case .toggleCommandBar:
                    return .concatenate(
                        .send(.shell(.setCommandBarFocusRestore(true))),
                        .send(.commandPalette(.togglePresentation))
                    )
                case .addProject,
                        .removeProject,
                        .addWorktree,
                        .deleteWorktree,
                        .selectProject,
                        .selectNextProject,
                        .selectPreviousProject,
                        .createAgent,
                        .createDefaultAgent,
                        .deleteAgent,
                        .selectPreviousAgent,
                        .selectNextAgent,
                        .toggleVoiceInput,
                        .openTerminalView,
                        .openVSCodeView,
                        .openAgentView,
                        .increaseTerminalFontSize,
                        .decreaseTerminalFontSize,
                        .togglePreviewPane,
                        .toggleRightSidebar,
                        .toggleLeftSidebar,
                        .quit:
                    return .send(.invokeCommand(
                        command,
                        projectContextID: nil,
                        workspaceContext: nil
                    ))
                }
            case let .invokeCommand(command, projectContextID, workspaceContext):
                let commandRouter = AppCommandRouter(appFeature: self)
                return commandRouter.handleCommandPaletteCommand(
                    &state,
                    command: command,
                    projectContextID: projectContextID,
                    workspaceContext: workspaceContext
                )
            case let .commandPalette(.delegate(.executeCommand(command, projectContextID, workspaceContext))):
                return .send(.invokeCommand(
                    command,
                    projectContextID: projectContextID,
                    workspaceContext: workspaceContext
                ))
            case let .commandPalette(.delegate(.submitTextInput(prompt))):
                return handleCommandPaletteTextInput(&state, prompt: prompt)
            case let .commandPalette(.delegate(.submitPickerItem(item))):
                return handleCommandPalettePickerItem(&state, item: item)
            case let .commandPalette(.delegate(.submitConfirmation(prompt))):
                return handleCommandPaletteConfirmation(&state, prompt: prompt)
            case .commandPalette(.executeCommand),
                    .commandPalette(.submit),
                    .commandPalette(.delegate):
                return .none
            case let .shell(.selectMainView(view)):
                state.workbench.selectOrCreateSurface(
                    for: view,
                    selection: state.workspace.projects.selection,
                    projects: state.workspace.projects,
                    agents: state.agent.agents
                )
                syncWorkbenchState(&state)
                syncEditorState(&state)
                return .merge(
                    surfaceStateChangedEffects(&state),
                    enforceVoiceInputContext(state)
                )
            case .shell(.selectPreviewView):
                syncWorkbenchState(&state, preferredSlot: .preview)
                syncEditorState(&state)
                return .merge(
                    surfaceStateChangedEffects(&state),
                    enforceVoiceInputContext(state)
                )
            case .shell(.persistLayout):
                let layout = state.shell.layout
                let projects = state.workspace.projects
                return .run { _ in
                    await layoutPersistenceClient.persistUIState(layout, projects)
                }
            case .shell(.togglePreview):
                syncWorkbenchState(
                    &state,
                    preferredSlot: state.shell.layout.previewEnabled ? .preview : .main
                )
                syncEditorState(&state)
                return .merge(
                    surfaceStateChangedEffects(&state),
                    enforceVoiceInputContext(state)
                )
            case .shell(.toggleTheme):
                return .send(.shell(.persistLayout))
            case let .agent(.selectSession(sessionID)):
                if let session = state.agent.agents.selectedSession {
                    state.workspace.projects.select(session.workspaceSelection)
                    state.editor.selectedWorkspaceID = session.workspaceSelection.stableID
                    state.shell.layout.selectMainView(.agent)
                    state.workbench.removeAgentWorkspaceTabs(for: session.workspaceSelection)
                    state.workbench.refreshAgentSessionTabIfNeeded(
                        sessionID: sessionID,
                        agents: state.agent.agents
                    )
                    state.workbench.selectOrCreateSurface(
                        for: .agent,
                        selection: session.workspaceSelection,
                        projects: state.workspace.projects,
                        agents: state.agent.agents
                    )
                    syncWorkbenchState(&state)
                    syncEditorState(&state)
                }
                return .merge(
                    surfaceStateChangedEffects(&state),
                    enforceVoiceInputContext(state)
                )
            case let .agent(.updateTerminalTitle(sessionID, _)):
                state.workbench.refreshAgentSessionTabIfNeeded(
                    sessionID: sessionID,
                    agents: state.agent.agents
                )
                return .none
            case let .agent(.delegate(.sessionLaunched(sessionID, workspaceSelection))):
                state.workspace.projects.select(workspaceSelection)
                state.editor.selectedWorkspaceID = workspaceSelection.stableID
                state.shell.layout.showsLeftSidebar = true
                state.shell.layout.selectMainView(.agent)
                state.workbench.removeAgentWorkspaceTabs(for: workspaceSelection)
                state.workbench.refreshAgentSessionTabIfNeeded(
                    sessionID: sessionID,
                    agents: state.agent.agents
                )
                state.workbench.selectOrCreateSurface(
                    for: .agent,
                    selection: workspaceSelection,
                    projects: state.workspace.projects,
                    agents: state.agent.agents
                )
                syncWorkbenchState(&state)
                syncEditorState(&state)
                return .concatenate(
                    closeCommandPalette(restorePreviousFocus: false),
                    .merge(
                        surfaceStateChangedEffects(&state),
                        enforceVoiceInputContext(state)
                    )
                )
            case let .agent(.delegate(.sessionsRemoved(sessionIDs))):
                guard !sessionIDs.isEmpty else {
                    return .none
                }
                for sessionID in sessionIDs {
                    state.workbench.removeSurfaceTabsForDeletedAgent(
                        sessionID,
                        layout: state.shell.layout,
                        projects: state.workspace.projects,
                        agents: state.agent.agents
                    )
                }
                syncWorkbenchState(&state)
                return syncTerminalActivationEffect(state)
            case .agent(.deleteSession),
                    .agent(.processTerminated),
                    .agent(.delegate),
                    .agent(.launchRequested),
                    .agent(.workspacesRemoved):
                return .none
            case let .workspace(.delegate(.selectionChanged(selection))):
                state.editor.selectedWorkspaceID = selection.stableID
                if state.agent.agents.selectedSession?.workspaceSelection != selection {
                    state.agent.agents.selectedSessionID = state.agent.agents.firstSession(in: selection)?.id
                }
                state.workbench.retargetTabsAfterWorkspaceSelection(
                    selection,
                    layout: state.shell.layout,
                    projects: state.workspace.projects,
                    agents: state.agent.agents
                )
                syncWorkbenchState(&state)
                syncEditorState(&state)
                return .merge(
                    surfaceStateChangedEffects(&state),
                    enforceVoiceInputContext(state)
                )
            case let .workspace(.delegate(.inventoryChanged(preferredSelection, revealSidebars, activateMainWindow))):
                applyWorkspaceInventoryChange(&state, preferredSelection: preferredSelection)
                if revealSidebars {
                    state.shell.layout.showsLeftSidebar = true
                    state.shell.layout.showsRightSidebar = true
                }
                let workspaceIDs = Array(Set(state.workspace.projects.orderedNodes.map(\.selection.stableID)))
                return .concatenate(
                    .send(.editor(.pruneWorkspaces(
                        keepingWorkspaceIDs: workspaceIDs,
                        fallbackSelectedWorkspaceID: state.workspace.projects.selection.stableID
                    ))),
                    isVSCodeVisible(in: state.shell.layout)
                        ? .send(.editor(.syncVisibleWorkspace(forceRestart: false)))
                        : .none,
                    .send(.shell(.setCommandBarFocusRestore(false))),
                    .send(.commandPalette(.close(restorePreviousFocus: false))),
                    activateMainWindow
                        ? .run { _ in
                            await appControlClient.activateMainWindowForExternalOpen()
                        }
                        : .none
                )
            case .workspace(.delegate(.configDiagnosticsUpdated)):
                return .run { @MainActor send in
                    do {
                        let loadResult = try await configClient.load()
                        send(.shell(.setResolvedShortcuts(loadResult.config.resolvedShortcuts)))
                        send(.shell(.setTerminalConfig(loadResult.config.terminal)))
                        send(.shell(.setThemeSet(loadResult.config.theme)))
                        send(.shell(.updateConfigDiagnosticsNotification(
                            configClient.diagnosticsMessage(
                                loadResult.diagnostics,
                                configClient.configURL()
                            )
                        )))
                    } catch {
                        // Keep workspace updates resilient when config reload fails.
                    }
                }
            case let .workspace(.delegate(.workspaceRemoved(selections))):
                return .concatenate(
                    .send(.agent(.workspacesRemoved(selections))),
                    .send(.editor(.workspacesRemoved(selections.map(\.stableID)))),
                    enforceVoiceInputContext(state)
                )
            case .workspace(.delegate(.projectImportCompleted(importedPaths: _, preferredSelection: _))):
                return .none
            case let .workspace(.delegate(.operationFailed(message))):
                return .send(.commandPaletteOperationFailed(message))
            case let .workspace(.delegate(.externalOpenFailed(detailMessage))):
                return .send(.shell(.setConfigNotification(
                    ConfigNotificationState(
                        title: "Cannot open workspace",
                        message: "Deep link could not be processed.",
                        detailMessage: detailMessage
                    )
                )))
            case .workspace(.toggleProjectCollapse),
                    .workspace(.toggleSectionCollapse):
                return .send(.shell(.persistLayout))
            case .lifecycle(.delegate(.appLaunched)):
                return .send(.appLaunched)
            case let .lifecycle(.delegate(.externalOpenRequested(request))):
                return .send(.workspace(.externalOpenRequested(request)))
            case let .lifecycle(.delegate(.externalOpenFailed(detailMessage))):
                return .send(.shell(.setConfigNotification(
                    ConfigNotificationState(
                        title: "Cannot open workspace",
                        message: "Deep link could not be processed.",
                        detailMessage: detailMessage
                    )
                )))
            case let .workbench(.selectSurfaceTab(surfaceID)):
                guard let tab = state.workbench.surfaceTabs.tabs.first(where: { $0.id == surfaceID }) else {
                    return .none
                }

                state.shell.layout.selectMainView(tab.mainView)
                state.workspace.projects.select(tab.workspaceSelection)
                state.editor.selectedWorkspaceID = tab.workspaceSelection.stableID

                switch surfaceID {
                case let .agentSession(sessionID):
                    state.agent.agents.selectSession(sessionID)
                case .agentWorkspace:
                    state.agent.agents.selectedSessionID = state.agent.agents.firstSession(in: tab.workspaceSelection)?.id
                case .workspaceTerminal, .vscodeWorkspace:
                    break
                }

                syncWorkbenchState(&state)
                syncEditorState(&state)
                return .merge(
                    surfaceStateChangedEffects(&state),
                    enforceVoiceInputContext(state)
                )
            case .toggleVoiceInput:
                if state.voiceInput.activeSessionID != nil {
                    Self.voiceInputTrace("toggle requested while active session=\(state.voiceInput.activeSessionID?.uuidString ?? "nil"), stopping")
                    return .send(.stopVoiceInput)
                }

                guard let targetSessionID = visibleAgentSessionID(in: state) else {
                    Self.voiceInputTrace("toggle requested without visible agent session")
                    return .send(.shell(.setConfigNotification(ConfigNotificationState(
                        title: "Voice input unavailable",
                        message: "Open an active agent session first.",
                        detailMessage: "Voice input can run only when main view is Agent with running session."
                    ))))
                }

                state.voiceInput.activeSessionID = targetSessionID
                state.voiceInput.hasInsertedText = false
                Self.voiceInputTrace("voice input started session=\(targetSessionID.uuidString)")
                return .run { [targetSessionID] send in
                    let stream = await voiceInputClient.start(targetSessionID)
                    for await event in stream {
                        await send(.voiceInputEvent(event))
                    }
                }
                .cancellable(id: voiceInputCancelID, cancelInFlight: true)
            case let .voiceInputEvent(event):
                Self.voiceInputTrace("voice event \(Self.voiceEventDebugSummary(event))")
                switch event {
                case let .transcriptDelta(rawText, _):
                    guard let sessionID = state.voiceInput.activeSessionID else {
                        Self.voiceInputTrace("drop transcript event: no active session")
                        return .none
                    }
                    let text = normalizedVoiceInputChunk(
                        rawText,
                        shouldInsertLeadingSpace: state.voiceInput.hasInsertedText
                    )
                    guard !text.isEmpty else {
                        return .none
                    }
                    state.voiceInput.hasInsertedText = true
                    return .run { _ in
                        let controller = await terminalRegistryClient.agentController(sessionID)
                        Self.voiceInputTrace(
                            "send transcript session=\(sessionID.uuidString) hasController=\(controller != nil) chars=\(text.count)"
                        )
                        await controller?.sendText(text)
                    }
                case .stopped:
                    Self.voiceInputTrace("voice input stopped session=\(state.voiceInput.activeSessionID?.uuidString ?? "nil")")
                    state.voiceInput.activeSessionID = nil
                    state.voiceInput.hasInsertedText = false
                    return .cancel(id: voiceInputCancelID)
                case let .failed(message):
                    Self.voiceInputTrace("voice input failed message=\(message)")
                    state.voiceInput.activeSessionID = nil
                    state.voiceInput.hasInsertedText = false
                    return .concatenate(
                        .cancel(id: voiceInputCancelID),
                        .send(.shell(.setConfigNotification(ConfigNotificationState(
                            title: "Voice input failed",
                            message: message,
                            detailMessage: "Check microphone and speech recognition permissions in System Settings, then retry."
                        ))))
                    )
                }
            case .stopVoiceInput:
                let activeSessionID = state.voiceInput.activeSessionID
                Self.voiceInputTrace("stop requested session=\(activeSessionID?.uuidString ?? "nil")")
                return .run { _ in
                    await voiceInputClient.stop()
                }
            case .lifecycle(.setApplicationActive), .lifecycle(.setWindowKey):
                return syncTerminalActivationEffect(state)
            case .shell, .workbench, .workspace, .agent, .editor, .commandPalette, .lifecycle:
                return .none
            }
        }
    }
}

private extension AppFeature {
    nonisolated static let voiceInputLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "dev.breuer.spurwechsel",
        category: "VoiceInputFlow"
    )
    nonisolated static func voiceInputTrace(_ message: String) {
        #if DEBUG
        print("[voice-input-flow] \(message)")
        #else
        voiceInputLogger.debug("\(message, privacy: .public)")
        #endif
    }

    var voiceInputCancelID: String { "voice-input-stream" }

    func visibleAgentSessionID(in state: State) -> UUID? {
        guard state.shell.layout.selectedMainView == .agent,
              let surfaceID = state.workbench.surfaceMountState.mainSurfaceID
        else {
            return nil
        }
        return resolvedAgentSessionID(
            for: surfaceID,
            tabs: state.workbench.surfaceTabs.tabs,
            agents: state.agent.agents
        )
    }

    func enforceVoiceInputContext(_ state: State) -> Effect<Action> {
        guard let activeSessionID = state.voiceInput.activeSessionID else {
            return .none
        }

        guard let visibleSessionID = visibleAgentSessionID(in: state),
              visibleSessionID == activeSessionID else {
            return .send(.stopVoiceInput)
        }

        return .none
    }

    func normalizedVoiceInputChunk(
        _ rawText: String,
        shouldInsertLeadingSpace: Bool
    ) -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }
        return shouldInsertLeadingSpace ? " \(trimmed)" : trimmed
    }

    nonisolated static func voiceEventDebugSummary(_ event: VoiceInputEvent) -> String {
        switch event {
        case let .transcriptDelta(text, isFinal):
            return "transcriptDelta chars=\(text.count) final=\(isFinal)"
        case .stopped:
            return "stopped"
        case let .failed(message):
            return "failed chars=\(message.count)"
        }
    }
}

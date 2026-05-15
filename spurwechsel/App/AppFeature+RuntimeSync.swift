import ComposableArchitecture
import Foundation

extension AppFeature {
    func syncWorkbenchState(
        _ state: inout State,
        preferredSlot: SurfaceSlot? = nil
    ) {
        state.workbench.syncMountedSurfaces(
            layout: state.shell.layout,
            projects: state.workspace.projects,
            agents: state.agent.agents
        )

        let resolvedPreferredSlot = preferredSlot ?? state.workbench.preferredSurfaceSlot(for: state.shell.layout)
        state.shell.surfaceFocusRequest = state.workbench.makeFocusRequest(
            preferredSlot: resolvedPreferredSlot,
            layout: state.shell.layout
        )
    }

    func syncEditorState(_ state: inout State) {
        let showsVSCodeInMain = state.shell.layout.selectedMainView == .vscode
        let showsVSCodeInPreview = state.shell.layout.previewEnabled && state.shell.layout.selectedPreviewView == .vscode

        guard showsVSCodeInMain || showsVSCodeInPreview else {
            return
        }

        state.editor.prepareVSCodeSelection(
            state.workspace.projects.selection,
            projects: state.workspace.projects
        )
    }

    func surfaceStateChangedEffects(
        _ state: inout State,
        forceVSCodeRestart: Bool = false
    ) -> Effect<Action> {
        .merge(
            syncVisibleWorkspaceTerminalControllers(state),
            syncTerminalActivationEffect(state),
            syncVisibleVSCodeRuntime(
                layout: state.shell.layout,
                forceRestart: forceVSCodeRestart
            )
        )
    }

    func syncTerminalActivationEffect(_ state: State) -> Effect<Action> {
        let surfacesAreForeground = state.lifecycle.terminalSurfacesAreForeground
        let activeSurfaceIDs = [
            state.workbench.surfaceMountState.mainSurfaceID,
            state.workbench.surfaceMountState.previewSurfaceID
        ].compactMap { $0 }
        let tabs = state.workbench.surfaceTabs.tabs
        let sessions = state.agent.agents.sessions
        let orderedNodes = state.workspace.projects.orderedNodes
        let activeAgentSessionID = surfacesAreForeground
            ? activeSurfaceIDs.compactMap {
                resolvedAgentSessionID(
                    for: $0,
                    tabs: tabs,
                    agents: state.agent.agents
                )
            }.first
            : nil
        let activeWorkspaceSelection = surfacesAreForeground
            ? activeSurfaceIDs.first(where: isWorkspaceTerminalSurface(_:)).flatMap {
                resolvedWorkspaceSelection(for: $0, tabs: tabs)
            }
            : nil
        let activeWorkspaceID = activeWorkspaceSelection?.stableID
        let activeWorkspacePath = activeWorkspaceSelection.flatMap {
            state.workspace.projects.path(for: $0)
        }
        let terminalTheme = state.shell.themeSet.terminalTheme

        return .run { @MainActor _ in
            for session in sessions {
                terminalRegistryClient.setAgentAttached(session.id, session.id == activeAgentSessionID)
            }

            for workspaceNode in orderedNodes {
                terminalRegistryClient.setWorkspaceAttached(workspaceNode.selection.stableID, false)
            }

            if let activeWorkspaceID, let activeWorkspacePath {
                _ = terminalRegistryClient.workspaceController(
                    activeWorkspaceID,
                    activeWorkspacePath,
                    terminalTheme
                )
                terminalRegistryClient.setWorkspaceAttached(activeWorkspaceID, true)
            }
        }
    }

    func syncVisibleWorkspaceTerminalControllers(_ state: State) -> Effect<Action> {
        let mountedSurfaceIDs = [
            state.workbench.surfaceMountState.mainSurfaceID,
            state.workbench.surfaceMountState.previewSurfaceID
        ].compactMap { $0 }
        let tabsByID = Dictionary(uniqueKeysWithValues: state.workbench.surfaceTabs.tabs.map { ($0.id, $0) })
        let terminalTheme = state.shell.themeSet.terminalTheme
        var workspaceTerminals: [(workspaceID: String, workspacePath: String)] = []
        var seenWorkspaceIDs: Set<String> = []

        for surfaceID in mountedSurfaceIDs {
            guard case let .workspaceTerminal(workspaceID) = surfaceID,
                  let tab = tabsByID[surfaceID],
                  let workspacePath = state.workspace.projects.path(for: tab.workspaceSelection),
                  seenWorkspaceIDs.insert(workspaceID).inserted
            else {
                continue
            }
            workspaceTerminals.append((workspaceID: workspaceID, workspacePath: workspacePath))
        }

        guard !workspaceTerminals.isEmpty else {
            return .none
        }

        return .run { @MainActor _ in
            for terminal in workspaceTerminals {
                _ = terminalRegistryClient.workspaceController(
                    terminal.workspaceID,
                    terminal.workspacePath,
                    terminalTheme
                )
            }
        }
    }

    func syncVisibleVSCodeRuntime(
        layout: AppLayoutState,
        forceRestart: Bool = false
    ) -> Effect<Action> {
        guard isVSCodeVisible(in: layout) else {
            return .none
        }
        return .send(.editor(.syncVisibleWorkspace(forceRestart: forceRestart)))
    }

    func resolvedAgentSessionID(
        for surfaceID: SurfaceTabID,
        tabs: [SurfaceTab],
        agents: AgentState
    ) -> UUID? {
        switch surfaceID {
        case let .agentSession(sessionID):
            return sessionID
        case let .agentWorkspace(selectionID):
            guard let tab = tabs.first(where: { $0.id == .agentWorkspace(selectionID) }) else {
                return nil
            }
            return agents.firstSession(in: tab.workspaceSelection)?.id
        default:
            return nil
        }
    }

    func resolvedWorkspaceSelection(
        for surfaceID: SurfaceTabID,
        tabs: [SurfaceTab]
    ) -> WorkspaceSelection? {
        switch surfaceID {
        case .workspaceTerminal, .agentWorkspace, .vscodeWorkspace:
            return tabs.first(where: { $0.id == surfaceID })?.workspaceSelection
        case .agentSession:
            return nil
        }
    }

    func isWorkspaceTerminalSurface(_ surfaceID: SurfaceTabID) -> Bool {
        if case .workspaceTerminal = surfaceID {
            return true
        }
        return false
    }

    func isVSCodeVisible(in layout: AppLayoutState) -> Bool {
        layout.selectedMainView == .vscode
            || (layout.previewEnabled && layout.selectedPreviewView == .vscode)
    }
}

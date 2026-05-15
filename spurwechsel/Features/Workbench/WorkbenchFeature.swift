import ComposableArchitecture
import Foundation

struct WorkbenchFeature: Reducer {
    @ObservableState
    struct State: Equatable {
        var surfaceTabs: SurfaceTabState
        var surfaceMountState: SurfaceMountState
        var nextSurfaceFocusRequestID: Int = 0

        var selectedSurfaceTab: SurfaceTab? {
            surfaceTabs.selectedTab
        }

        mutating func initializeDefaultTabs(
            layout: AppLayoutState,
            projects: ProjectsState,
            agents: AgentState
        ) {
            surfaceTabs = SurfaceTabState()
            selectOrCreateSurface(
                for: layout.selectedMainView,
                selection: projects.selection,
                projects: projects,
                agents: agents
            )
            syncMountedSurfaces(
                layout: layout,
                projects: projects,
                agents: agents
            )
        }

        mutating func selectSurfaceTab(_ id: SurfaceTabID) {
            guard surfaceTabs.tabs.contains(where: { $0.id == id }) else {
                return
            }
            surfaceTabs.selectedTabID = id
        }

        mutating func selectOrCreateSurface(
            for mainView: MainViewKind,
            selection: WorkspaceSelection,
            projects: ProjectsState,
            agents: AgentState
        ) {
            switch mainView {
            case .agent:
                selectOrCreateAgentTab(for: selection, projects: projects, agents: agents)
            case .terminal:
                upsertSurfaceTab(makeWorkspaceTerminalTab(for: selection, projects: projects), select: true)
            case .vscode:
                upsertSurfaceTab(makeVSCodeWorkspaceTab(for: selection, projects: projects), select: true)
            }
        }

        mutating func refreshAgentSessionTabIfNeeded(
            sessionID: UUID,
            agents: AgentState
        ) {
            let tabID = SurfaceTabID.agentSession(sessionID)
            guard surfaceTabs.tabs.contains(where: { $0.id == tabID }) else {
                return
            }
            guard let session = agents.sessions.first(where: { $0.id == sessionID }) else {
                return
            }
            upsertSurfaceTab(makeAgentSessionTab(session), select: false)
        }

        mutating func retargetTabsAfterWorkspaceSelection(
            _ selection: WorkspaceSelection,
            layout: AppLayoutState,
            projects: ProjectsState,
            agents: AgentState
        ) {
            guard let selectedID = surfaceTabs.selectedTabID else {
                selectOrCreateSurface(
                    for: layout.selectedMainView,
                    selection: selection,
                    projects: projects,
                    agents: agents
                )
                return
            }

            switch selectedID {
            case .workspaceTerminal:
                upsertSurfaceTab(makeWorkspaceTerminalTab(for: selection, projects: projects), select: true)
            case .vscodeWorkspace:
                upsertSurfaceTab(makeVSCodeWorkspaceTab(for: selection, projects: projects), select: true)
            case .agentSession:
                if let selectedSession = agents.selectedSession {
                    upsertSurfaceTab(makeAgentSessionTab(selectedSession), select: true)
                } else {
                    selectOrCreateAgentTab(for: selection, projects: projects, agents: agents)
                }
            case .agentWorkspace:
                selectOrCreateAgentTab(for: selection, projects: projects, agents: agents)
            }
        }

        mutating func removeAgentWorkspaceTabs(for selection: WorkspaceSelection) {
            surfaceTabs.tabs.removeAll { tab in
                if case let .agentWorkspace(selectionID) = tab.id {
                    return selectionID == selection.stableID
                }
                return false
            }
            if let selectedTabID = surfaceTabs.selectedTabID,
               !surfaceTabs.tabs.contains(where: { $0.id == selectedTabID }) {
                surfaceTabs.selectedTabID = surfaceTabs.tabs.last?.id
            }
        }

        mutating func removeSurfaceTabsForDeletedAgent(
            _ sessionID: UUID,
            layout: AppLayoutState,
            projects: ProjectsState,
            agents: AgentState
        ) {
            let removedID = SurfaceTabID.agentSession(sessionID)
            let wasSelected = surfaceTabs.selectedTabID == removedID
            surfaceTabs.tabs.removeAll { $0.id == removedID }

            guard wasSelected else {
                return
            }

            selectOrCreateSurface(
                for: layout.selectedMainView,
                selection: projects.selection,
                projects: projects,
                agents: agents
            )
        }

        mutating func pruneInvalidTabs(
            keepingSelections: Set<WorkspaceSelection>,
            validSessionIDs: Set<UUID>,
            layout: AppLayoutState,
            projects: ProjectsState,
            agents: AgentState
        ) {
            surfaceTabs.tabs.removeAll { tab in
                guard keepingSelections.contains(tab.workspaceSelection) else {
                    return true
                }
                if let sessionID = tab.sessionID {
                    return !validSessionIDs.contains(sessionID)
                }
                return false
            }

            if let selectedID = surfaceTabs.selectedTabID,
               surfaceTabs.tabs.contains(where: { $0.id == selectedID }) {
                return
            }

            selectOrCreateSurface(
                for: layout.selectedMainView,
                selection: projects.selection,
                projects: projects,
                agents: agents
            )
        }

        mutating func syncMountedSurfaces(
            layout: AppLayoutState,
            projects: ProjectsState,
            agents: AgentState
        ) {
            surfaceMountState.mount(surfaceTabs.selectedTabID, in: .main)

            guard layout.previewEnabled,
                  let previewView = layout.selectedPreviewView,
                  let previewSurfaceID = resolveSurfaceID(
                    for: previewView,
                    selection: projects.selection,
                    projects: projects,
                    agents: agents
                  )
            else {
                surfaceMountState.mount(nil, in: .preview)
                return
            }

            if previewSurfaceID == surfaceTabs.selectedTabID {
                surfaceMountState.mount(nil, in: .preview)
                return
            }

            upsertSurfaceTabIfNeeded(
                for: previewSurfaceID,
                selection: projects.selection,
                projects: projects,
                agents: agents
            )
            surfaceMountState.mount(previewSurfaceID, in: .preview)
        }

        func preferredSurfaceSlot(for layout: AppLayoutState) -> SurfaceSlot {
            let preferred = layout.preferredFocusedSlot(for: layout.selectedMainView)
            if preferred == .preview,
               layout.previewEnabled,
               surfaceMountState.previewSurfaceID != nil {
                return .preview
            }
            return .main
        }

        mutating func makeFocusRequest(
            preferredSlot: SurfaceSlot,
            layout: AppLayoutState
        ) -> SurfaceFocusRequest? {
            let resolvedSlot: SurfaceSlot
            switch preferredSlot {
            case .main:
                if surfaceMountState.mainSurfaceID != nil {
                    resolvedSlot = .main
                } else if surfaceMountState.previewSurfaceID != nil {
                    resolvedSlot = .preview
                } else {
                    return nil
                }
            case .preview:
                if layout.previewEnabled,
                   surfaceMountState.previewSurfaceID != nil {
                    resolvedSlot = .preview
                } else if surfaceMountState.mainSurfaceID != nil {
                    resolvedSlot = .main
                } else {
                    return nil
                }
            }

            nextSurfaceFocusRequestID += 1
            return SurfaceFocusRequest(
                id: nextSurfaceFocusRequestID,
                slot: resolvedSlot
            )
        }

        private mutating func selectOrCreateAgentTab(
            for selection: WorkspaceSelection,
            projects: ProjectsState,
            agents: AgentState
        ) {
            if let selectedSession = agents.selectedSession,
               selectedSession.workspaceSelection == selection {
                upsertSurfaceTab(makeAgentSessionTab(selectedSession), select: true)
                return
            }

            if let firstSession = agents.firstSession(in: selection) {
                upsertSurfaceTab(makeAgentSessionTab(firstSession), select: true)
                return
            }

            upsertSurfaceTab(makeAgentWorkspaceTab(for: selection, projects: projects), select: true)
        }

        private mutating func upsertSurfaceTab(_ tab: SurfaceTab, select: Bool) {
            if let index = surfaceTabs.tabs.firstIndex(where: { $0.id == tab.id }) {
                surfaceTabs.tabs[index] = tab
            } else {
                surfaceTabs.tabs.append(tab)
            }

            if select {
                surfaceTabs.selectedTabID = tab.id
            }
        }

        private mutating func upsertSurfaceTabIfNeeded(
            for id: SurfaceTabID,
            selection: WorkspaceSelection,
            projects: ProjectsState,
            agents: AgentState
        ) {
            if surfaceTabs.tabs.contains(where: { $0.id == id }) {
                return
            }

            switch id {
            case let .agentSession(sessionID):
                if let session = agents.sessions.first(where: { $0.id == sessionID }) {
                    upsertSurfaceTab(makeAgentSessionTab(session), select: false)
                }
            case .agentWorkspace:
                upsertSurfaceTab(makeAgentWorkspaceTab(for: selection, projects: projects), select: false)
            case .workspaceTerminal:
                upsertSurfaceTab(makeWorkspaceTerminalTab(for: selection, projects: projects), select: false)
            case .vscodeWorkspace:
                upsertSurfaceTab(makeVSCodeWorkspaceTab(for: selection, projects: projects), select: false)
            }
        }

        private func resolveSurfaceID(
            for previewView: PreviewViewKind,
            selection: WorkspaceSelection,
            projects: ProjectsState,
            agents: AgentState
        ) -> SurfaceTabID? {
            switch previewView {
            case .agent:
                if let selectedSession = agents.selectedSession,
                   selectedSession.workspaceSelection == selection {
                    return .agentSession(selectedSession.id)
                }
                if let firstSession = agents.firstSession(in: selection) {
                    return .agentSession(firstSession.id)
                }
                return .agentWorkspace(selection.stableID)
            case .terminal:
                guard projects.path(for: selection) != nil else {
                    return nil
                }
                return .workspaceTerminal(selection.stableID)
            case .vscode:
                guard projects.path(for: selection) != nil else {
                    return nil
                }
                return .vscodeWorkspace(selection.stableID)
            }
        }
    }

    enum Action {
        case selectSurfaceTab(SurfaceTabID)
        case setSurfaceTabs(SurfaceTabState)
        case setSurfaceMountState(SurfaceMountState)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .selectSurfaceTab(surfaceID):
                state.selectSurfaceTab(surfaceID)
            case let .setSurfaceTabs(surfaceTabs):
                state.surfaceTabs = surfaceTabs
            case let .setSurfaceMountState(surfaceMountState):
                state.surfaceMountState = surfaceMountState
            }
            return .none
        }
    }
}

private func makeAgentSessionTab(_ session: AgentSession) -> SurfaceTab {
    SurfaceTab(
        id: .agentSession(session.id),
        title: session.name,
        workspaceSelection: session.workspaceSelection,
        sessionID: session.id
    )
}

private func makeAgentWorkspaceTab(
    for selection: WorkspaceSelection,
    projects: ProjectsState
) -> SurfaceTab {
    let title = projects.node(for: selection)?.title ?? "Agent"
    return SurfaceTab(
        id: .agentWorkspace(selection.stableID),
        title: "Agent • \(title)",
        workspaceSelection: selection,
        sessionID: nil
    )
}

private func makeWorkspaceTerminalTab(
    for selection: WorkspaceSelection,
    projects: ProjectsState
) -> SurfaceTab {
    let title = projects.node(for: selection)?.title ?? "terminal"
    return SurfaceTab(
        id: .workspaceTerminal(selection.stableID),
        title: "Terminal • \(title)",
        workspaceSelection: selection,
        sessionID: nil
    )
}

private func makeVSCodeWorkspaceTab(
    for selection: WorkspaceSelection,
    projects: ProjectsState
) -> SurfaceTab {
    let title = projects.node(for: selection)?.title ?? "vscode"
    return SurfaceTab(
        id: .vscodeWorkspace(selection.stableID),
        title: "VSCode • \(title)",
        workspaceSelection: selection,
        sessionID: nil
    )
}

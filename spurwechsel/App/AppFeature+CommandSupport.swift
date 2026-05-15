import ComposableArchitecture
import Foundation

extension AppFeature {
    func handleTerminalFontSizeAdjustment(
        _ state: inout State,
        direction: Int,
        commandTitle: String
    ) -> Effect<Action> {
        guard let controller = focusedTerminalController(in: state) else {
            guard state.commandPalette.commandBar.isPresented else {
                return .none
            }

            return presentCommandPaletteError(
                "Focus an agent terminal or project terminal first, then run \(commandTitle).",
                projectContextID: state.commandPalette.commandBar.projectContextID,
                workspaceContext: state.commandPalette.commandBar.workspaceContext,
                ensurePresented: true
            )
        }

        guard let adjustedSize = adjustedTerminalFontSize(
            currentSize: controller.effectiveSurfaceFontSize,
            direction: direction
        ) else {
            return .none
        }

        state.shell.layout.terminalFontSizeOverride = adjustedSize
        terminalRegistryClient.setGlobalSurfaceFontSizeOverride(adjustedSize)

        return .concatenate(
            state.commandPalette.commandBar.isPresented
                ? closeCommandPalette(restorePreviousFocus: false)
                : .none,
            .send(.shell(.persistLayout))
        )
    }

    func adjustedTerminalFontSize(
        currentSize: Float,
        direction: Int
    ) -> Float? {
        guard direction != 0 else {
            return nil
        }

        let step: Float = 1.0
        let minSize: Float = 1.0
        let signedStep = direction > 0 ? step : -step
        let nextSize = max(minSize, currentSize + signedStep)
        if nextSize == currentSize {
            return nil
        }
        return nextSize
    }

    func focusedTerminalController(
        in state: State
    ) -> LocalShellTerminalSessionController? {
        guard let surfaceID = focusedSurfaceID(in: state) else {
            return nil
        }

        switch surfaceID {
        case let .agentSession(sessionID):
            return terminalRegistryClient.agentController(sessionID)
        case let .agentWorkspace(selectionID):
            guard let tab = state.workbench.surfaceTabs.tabs.first(
                where: { $0.id == .agentWorkspace(selectionID) }
            ) else {
                return nil
            }
            if let selectedSession = state.agent.agents.selectedSession,
               selectedSession.workspaceSelection == tab.workspaceSelection {
                return terminalRegistryClient.agentController(selectedSession.id)
            }
            guard let fallbackSession = state.agent.agents.firstSession(in: tab.workspaceSelection) else {
                return nil
            }
            return terminalRegistryClient.agentController(fallbackSession.id)
        case let .workspaceTerminal(workspaceID):
            return terminalRegistryClient.workspaceControllerIfLoaded(workspaceID)
        case .vscodeWorkspace:
            return nil
        }
    }

    func focusedSurfaceID(in state: State) -> SurfaceTabID? {
        let preferredSlot = state.shell.layout.preferredFocusedSlot(for: state.shell.layout.selectedMainView)
        let resolvedSlot: SurfaceSlot = preferredSlot == .preview && !state.shell.layout.previewEnabled
            ? .main
            : preferredSlot
        switch resolvedSlot {
        case .main:
            return state.workbench.surfaceMountState.mainSurfaceID
        case .preview:
            return state.workbench.surfaceMountState.previewSurfaceID
        }
    }

    func presentCommandPaletteError(
        _ text: String,
        projectContextID: UUID?,
        workspaceContext: WorkspaceSelection?,
        ensurePresented: Bool
    ) -> Effect<Action> {
        .send(.commandPalette(.presentError(
            text,
            projectContextID: projectContextID,
            workspaceContext: workspaceContext,
            ensurePresented: ensurePresented
        )))
    }

    func setCommandPaletteNotice(
        _ notice: CommandBarNotice?
    ) -> Effect<Action> {
        .send(.commandPalette(.setNotice(notice)))
    }

    func closeCommandPalette(
        restorePreviousFocus: Bool
    ) -> Effect<Action> {
        .concatenate(
            .send(.shell(.setCommandBarFocusRestore(restorePreviousFocus))),
            .send(.commandPalette(.close(restorePreviousFocus: restorePreviousFocus)))
        )
    }

    func resolveProjectContextID(
        in state: State,
        preferred: UUID?
    ) -> UUID? {
        if let preferred {
            return preferred
        }
        switch state.workspace.projects.selection {
        case let .project(projectID):
            return projectID
        case let .worktree(worktreeID):
            return state.workspace.projects.projectForWorktree(id: worktreeID)?.id
        }
    }

    func resolveWorkspaceContext(
        in state: State,
        preferred: WorkspaceSelection?
    ) -> WorkspaceSelection? {
        if let preferred,
           state.workspace.projects.path(for: preferred) != nil {
            return preferred
        }
        if state.workspace.projects.path(for: state.workspace.projects.selection) != nil {
            return state.workspace.projects.selection
        }
        if let firstProject = state.workspace.projects.projects.first {
            return .project(firstProject.id)
        }
        return nil
    }

    func adjacentWorkspaceSelection(
        in projects: ProjectsState,
        offset: Int
    ) -> WorkspaceSelection? {
        let selections = projects.projects.flatMap { project in
            [WorkspaceSelection.project(project.id)]
                + project.worktrees.map { WorkspaceSelection.worktree($0.id) }
        }

        return adjacentEntry(
            from: projects.selection,
            in: selections,
            offset: offset
        )
    }

    func adjacentAgentSessionID(
        in state: State,
        offset: Int
    ) -> UUID? {
        let sessionIDs = state.workspace.projects.orderedNodes.flatMap { node in
            state.agent.agents.sessions(for: node.selection).map(\.id)
        }

        return adjacentEntry(
            from: state.agent.agents.selectedSessionID,
            in: sessionIDs,
            offset: offset
        )
    }

    func adjacentEntry<T: Equatable>(
        from current: T,
        in entries: [T],
        offset: Int
    ) -> T? {
        guard !entries.isEmpty else {
            return nil
        }

        guard let currentIndex = entries.firstIndex(of: current) else {
            return offset >= 0 ? entries.first : entries.last
        }

        let nextIndex = (currentIndex + offset + entries.count) % entries.count
        return entries[nextIndex]
    }

    func adjacentEntry<T: Equatable>(
        from current: T?,
        in entries: [T],
        offset: Int
    ) -> T? {
        guard !entries.isEmpty else {
            return nil
        }

        guard let current else {
            return offset >= 0 ? entries.first : entries.last
        }

        return adjacentEntry(from: current, in: entries, offset: offset)
    }
}

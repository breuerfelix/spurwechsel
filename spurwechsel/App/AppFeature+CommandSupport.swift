import ComposableArchitecture
import Foundation

extension AppFeature {
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

import Foundation

extension AppFeature {
    func applyWorkspaceInventoryChange(
        _ state: inout State,
        preferredSelection: WorkspaceSelection?
    ) {
        if let preferredSelection,
           state.workspace.projects.projects.contains(where: { $0.contains(preferredSelection) }) {
            state.workspace.projects.select(preferredSelection)
        }

        let validSelections = Set(state.workspace.projects.orderedNodes.map(\.selection))

        state.workbench.retargetTabsAfterWorkspaceSelection(
            state.workspace.projects.selection,
            layout: state.shell.layout,
            projects: state.workspace.projects,
            agents: state.agent.agents
        )
        state.workbench.pruneInvalidTabs(
            keepingSelections: validSelections,
            validSessionIDs: Set(state.agent.agents.sessions.map(\.id)),
            layout: state.shell.layout,
            projects: state.workspace.projects,
            agents: state.agent.agents
        )
        syncWorkbenchState(&state)
        syncEditorState(&state)
    }
}

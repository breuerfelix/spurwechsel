import Foundation

enum PreviewFixtures {
    static let tiltrunProject = Project(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        name: "TiltRun",
        branch: "main"
    )

    static let orbitProject = Project(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        name: "Orbit",
        branch: "main"
    )

    static let draftframeEditor = Worktree(
        id: UUID(uuidString: "33333333-3333-3333-3333-333333333331")!,
        name: "editor",
        branch: "editor"
    )

    static let draftframeExporting = Worktree(
        id: UUID(uuidString: "33333333-3333-3333-3333-333333333332")!,
        name: "exporting",
        branch: "exporting"
    )

    static let draftframeProject = Project(
        id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
        name: "draftframe",
        branch: "main",
        worktrees: [draftframeEditor, draftframeExporting]
    )

    static let sidetrackSpurwechsel = Worktree(
        id: UUID(uuidString: "44444444-4444-4444-4444-444444444441")!,
        name: "spurwechsel",
        branch: "spurwechsel"
    )

    static let sidetrackProject = Project(
        id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
        name: "sidetrack",
        branch: "main",
        worktrees: [sidetrackSpurwechsel]
    )

    static let projectsState = ProjectsState(
        projects: [tiltrunProject, orbitProject, draftframeProject, sidetrackProject],
        collapsedProjectIDs: [],
        selection: .worktree(draftframeExporting.id),
        nextProjectCount: 5,
        nextWorktreeCount: 3
    )

    static let layoutState = AppLayoutState(
        selectedMainView: .agent,
        previewConfigurations: [:],
        showsLeftSidebar: true,
        showsRightSidebar: true,
        themeMode: .dark
    )

    static let agentState = AgentState(
        sessions: [],
        selectedSessionID: nil,
        nextAgentCount: 1
    )

    static let vscodeIdleState = VSCodeServerState(
        workspaceSelectionID: projectsState.selection.stableID,
        workspaceName: "draftframe",
        workspacePath: "/tmp/draftframe",
        serverAddress: nil,
        workspaceAddress: nil,
        status: .idle,
        statusMessage: "Select VSCode view to start code-server.",
        errorMessage: nil,
        lastOutputLine: nil
    )

    static let vscodeStartingState = VSCodeServerState(
        workspaceSelectionID: projectsState.selection.stableID,
        workspaceName: "draftframe",
        workspacePath: "/tmp/draftframe",
        serverAddress: "http://127.0.0.1:19001/",
        workspaceAddress: nil,
        status: .starting,
        statusMessage: "Starting code-server for draftframe at 127.0.0.1:19001…",
        errorMessage: nil,
        lastOutputLine: "HTTP server listening on http://127.0.0.1:19001/"
    )

    static let vscodeRunningState = VSCodeServerState(
        workspaceSelectionID: projectsState.selection.stableID,
        workspaceName: "draftframe",
        workspacePath: "/tmp/draftframe",
        serverAddress: "http://127.0.0.1:19001/",
        workspaceAddress: "http://127.0.0.1:19001/?folder=/tmp/draftframe",
        status: .running,
        statusMessage: "code-server active for draftframe at http://127.0.0.1:19001/.",
        errorMessage: nil,
        lastOutputLine: "HTTP server listening on http://127.0.0.1:19001/"
    )

    static let vscodeStoppedState = VSCodeServerState(
        workspaceSelectionID: projectsState.selection.stableID,
        workspaceName: "draftframe",
        workspacePath: "/tmp/draftframe",
        serverAddress: nil,
        workspaceAddress: nil,
        status: .stopped,
        statusMessage: "code-server stopped. Switch back to VSCode view to relaunch.",
        errorMessage: nil,
        lastOutputLine: nil
    )

    static let vscodeFailureState = VSCodeServerState(
        workspaceSelectionID: projectsState.selection.stableID,
        workspaceName: "draftframe",
        workspacePath: "/tmp/draftframe",
        serverAddress: nil,
        workspaceAddress: nil,
        status: .startupFailed,
        statusMessage: "code-server exited before URL was ready (code 1).",
        errorMessage: "code-server exited before URL was ready (code 1).",
        lastOutputLine: "Error: address already in use."
    )

    static let previewModels = [
        PreviewContentModel(
            id: .agent,
            title: "Agent",
            symbolName: PreviewViewKind.agent.symbolName,
            subtitle: "Agent surface"
        ),
        PreviewContentModel(
            id: .terminal,
            title: "Terminal",
            symbolName: PreviewViewKind.terminal.symbolName,
            subtitle: "Terminal surface"
        ),
        PreviewContentModel(
            id: .vscode,
            title: "VSCode",
            symbolName: PreviewViewKind.vscode.symbolName,
            subtitle: "Editor surface"
        )
    ]
}

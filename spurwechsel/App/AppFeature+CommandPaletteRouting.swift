import ComposableArchitecture
import Foundation

extension AppFeature {
    func handleCommandPaletteCommand(
        _ state: inout State,
        command: CommandID,
        projectContextID: UUID?,
        workspaceContext: WorkspaceSelection?
    ) -> Effect<Action> {
        switch command {
        case .toggleCommandBar:
            return .concatenate(
                .send(.shell(.setCommandBarFocusRestore(true))),
                .send(.commandPalette(.togglePresentation))
            )
        case .addProject:
            return .concatenate(
                closeCommandPalette(restorePreviousFocus: false),
                .run { @MainActor send in
                    guard let selectedURLs = await importPanelClient.selectProjectDirectories(),
                          !selectedURLs.isEmpty else {
                        return
                    }
                    await send(.workspace(.importRequested(selectedURLs, activateMainWindow: false)))
                }
            )
        case .addWorktree:
            guard let resolvedProjectID = resolveProjectContextID(
                in: state,
                preferred: projectContextID
            ),
            let project = state.workspace.projects.project(id: resolvedProjectID) else {
                return presentCommandPaletteError(
                    "Select project first, then run Add Worktree.",
                    projectContextID: projectContextID,
                    workspaceContext: workspaceContext,
                    ensurePresented: !state.commandPalette.commandBar.isPresented
                )
            }
            guard project.isGitRepository else {
                return presentCommandPaletteError(
                    "Selected project is not a Git repository.",
                    projectContextID: resolvedProjectID,
                    workspaceContext: workspaceContext,
                    ensurePresented: !state.commandPalette.commandBar.isPresented
                )
            }
            return .send(.commandPalette(.presentTextInput(
                CommandBarTextPrompt(
                    title: "Add Worktree (\(project.name))",
                    placeholder: "Enter worktree name",
                    submitTitle: "Create Worktree",
                    action: .addWorktree(projectID: resolvedProjectID)
                ),
                projectContextID: resolvedProjectID,
                workspaceContext: workspaceContext
            )))
        case .removeProject:
            guard let resolvedProjectID = resolveProjectContextID(
                in: state,
                preferred: projectContextID
            ),
            let project = state.workspace.projects.project(id: resolvedProjectID) else {
                return presentCommandPaletteError(
                    "Select project first, then run Remove Project.",
                    projectContextID: projectContextID,
                    workspaceContext: workspaceContext,
                    ensurePresented: !state.commandPalette.commandBar.isPresented
                )
            }
            return .send(.commandPalette(.presentConfirmation(
                CommandBarConfirmationPrompt(
                    title: "Remove Project",
                    message: "Remove project '\(project.name)' from config and close related sessions? Files stay on disk.",
                    confirmTitle: "Remove Project",
                    action: .removeProject(projectID: resolvedProjectID)
                ),
                projectContextID: resolvedProjectID,
                workspaceContext: workspaceContext
            )))
        case .deleteWorktree:
            guard let resolvedProjectID = resolveProjectContextID(
                in: state,
                preferred: state.commandPalette.commandBar.projectContextID
            ),
            let project = state.workspace.projects.project(id: resolvedProjectID) else {
                return presentCommandPaletteError(
                    "Select project first, then run Delete Worktree.",
                    projectContextID: state.commandPalette.commandBar.projectContextID,
                    workspaceContext: workspaceContext,
                    ensurePresented: !state.commandPalette.commandBar.isPresented
                )
            }
            guard project.isGitRepository else {
                return presentCommandPaletteError(
                    "Selected project is not a Git repository.",
                    projectContextID: resolvedProjectID,
                    workspaceContext: workspaceContext,
                    ensurePresented: !state.commandPalette.commandBar.isPresented
                )
            }
            let items = project.worktrees.map { worktree in
                CommandBarPickerItem(
                    id: "worktree-\(worktree.id.uuidString)",
                    title: worktree.name,
                    subtitle: worktree.branch,
                    symbolName: "trash",
                    payload: .deleteWorktree(projectID: resolvedProjectID, worktreeID: worktree.id)
                )
            }
            return .send(.commandPalette(.presentPicker(
                title: "Delete Worktree (\(project.name))",
                items: items,
                emptyMessage: "No worktrees available.",
                projectContextID: resolvedProjectID,
                workspaceContext: workspaceContext
            )))
        case .selectProject:
            let items = state.workspace.projects.orderedNodes.map { node in
                CommandBarPickerItem(
                    id: "workspace-\(node.id)",
                    title: node.title,
                    subtitle: node.branchName,
                    symbolName: node.isProject ? "folder" : "point.3.filled.connected.trianglepath.dotted",
                    payload: .selectWorkspace(node.selection),
                    primarySearchText: node.title,
                    secondarySearchText: node.branchName,
                    secondarySearchPenalty: 50
                )
            }
            return .send(.commandPalette(.presentPicker(
                title: "Select Project",
                items: items,
                emptyMessage: "No projects available.",
                projectContextID: nil,
                workspaceContext: nil
            )))
        case .selectNextProject:
            guard let nextSelection = adjacentWorkspaceSelection(
                in: state.workspace.projects,
                offset: 1
            ) else {
                return .none
            }
            return .concatenate(
                closeCommandPalette(restorePreviousFocus: false),
                .send(.workspace(.selectWorkspace(nextSelection)))
            )
        case .selectPreviousProject:
            guard let previousSelection = adjacentWorkspaceSelection(
                in: state.workspace.projects,
                offset: -1
            ) else {
                return .none
            }
            return .concatenate(
                closeCommandPalette(restorePreviousFocus: false),
                .send(.workspace(.selectWorkspace(previousSelection)))
            )
        case .createAgent:
            guard let resolvedSelection = resolveWorkspaceContext(
                in: state,
                preferred: workspaceContext
            ) else {
                return presentCommandPaletteError(
                    "Select project or worktree first, then run Create Agent.",
                    projectContextID: nil,
                    workspaceContext: workspaceContext,
                    ensurePresented: !state.commandPalette.commandBar.isPresented
                )
            }
            guard state.workspace.projects.path(for: resolvedSelection) != nil else {
                return presentCommandPaletteError(
                    "Selected workspace has no launch path.",
                    projectContextID: nil,
                    workspaceContext: workspaceContext,
                    ensurePresented: !state.commandPalette.commandBar.isPresented
                )
            }

            return .run { @MainActor send in
                do {
                    let loadResult = try await configClient.load()
                    let items = loadResult.config.resolvedAgents.map { agent in
                        CommandBarPickerItem(
                            id: "agent-\(agent.displayName.lowercased().accessibilitySlug)",
                            title: agent.displayName,
                            subtitle: agent.normalizedCommand,
                            symbolName: "sparkles.rectangle.stack",
                            payload: .createAgent(
                                workspaceSelection: resolvedSelection,
                                agentName: agent.displayName,
                                command: agent.normalizedCommand
                            )
                        )
                    }
                    send(.commandPalette(.presentPicker(
                        title: "Create Agent",
                        items: items,
                        emptyMessage: "No agents configured.",
                        projectContextID: nil,
                        workspaceContext: resolvedSelection
                    )))
                } catch {
                    send(.commandPaletteOperationFailed(error.localizedDescription))
                }
            }
        case .createDefaultAgent:
            guard let resolvedSelection = resolveWorkspaceContext(
                in: state,
                preferred: workspaceContext
            ) else {
                return presentCommandPaletteError(
                    "Select project or worktree first, then run Create Default Agent.",
                    projectContextID: nil,
                    workspaceContext: workspaceContext,
                    ensurePresented: !state.commandPalette.commandBar.isPresented
                )
            }
            guard let workingDirectory = state.workspace.projects.path(for: resolvedSelection) else {
                return presentCommandPaletteError(
                    "Selected workspace has no launch path.",
                    projectContextID: nil,
                    workspaceContext: workspaceContext,
                    ensurePresented: !state.commandPalette.commandBar.isPresented
                )
            }
            let terminalTheme = state.shell.themeSet.terminalTheme

            return .run { @MainActor send in
                do {
                    let loadResult = try await configClient.load()
                    let defaultAgent = loadResult.config.resolvedDefaultAgent
                    send(.agent(.launchRequested(AgentLaunchRequest(
                        workspaceSelection: resolvedSelection,
                        workingDirectory: workingDirectory,
                        agentName: defaultAgent.displayName,
                        command: defaultAgent.normalizedCommand,
                        terminalTheme: terminalTheme
                    ))))
                } catch {
                    send(.commandPaletteOperationFailed(error.localizedDescription))
                }
            }
        case .deleteAgent:
            guard let session = state.agent.agents.selectedSession else {
                return presentCommandPaletteError(
                    "Select an agent session first, then run Delete Agent.",
                    projectContextID: nil,
                    workspaceContext: nil,
                    ensurePresented: !state.commandPalette.commandBar.isPresented
                )
            }
            return .send(.commandPalette(.presentConfirmation(
                CommandBarConfirmationPrompt(
                    title: "Delete Agent",
                    message: "Close and remove \(session.name)?",
                    confirmTitle: "Delete Agent",
                    action: .deleteAgent(sessionID: session.id)
                ),
                projectContextID: nil,
                workspaceContext: nil
            )))
        case .selectPreviousAgent:
            guard let previousSessionID = adjacentAgentSessionID(
                in: state,
                offset: -1
            ) else {
                return .none
            }
            return .concatenate(
                closeCommandPalette(restorePreviousFocus: false),
                .send(.agent(.selectSession(previousSessionID)))
            )
        case .selectNextAgent:
            guard let nextSessionID = adjacentAgentSessionID(
                in: state,
                offset: 1
            ) else {
                return .none
            }
            return .concatenate(
                closeCommandPalette(restorePreviousFocus: false),
                .send(.agent(.selectSession(nextSessionID)))
            )
        case .openTerminalView:
            return .concatenate(
                closeCommandPalette(restorePreviousFocus: false),
                .send(.shell(.selectMainView(.terminal)))
            )
        case .openVSCodeView:
            return .concatenate(
                closeCommandPalette(restorePreviousFocus: false),
                .send(.shell(.selectMainView(.vscode)))
            )
        case .openAgentView:
            return .concatenate(
                closeCommandPalette(restorePreviousFocus: false),
                .send(.shell(.selectMainView(.agent)))
            )
        case .toggleVoiceInput:
            return .concatenate(
                closeCommandPalette(restorePreviousFocus: false),
                .send(.toggleVoiceInput)
            )
        case .togglePreviewPane:
            return .concatenate(
                closeCommandPalette(restorePreviousFocus: false),
                .send(.shell(.togglePreview))
            )
        case .toggleRightSidebar:
            return .concatenate(
                closeCommandPalette(restorePreviousFocus: false),
                .send(.shell(.toggleRightSidebar))
            )
        case .toggleLeftSidebar:
            return .concatenate(
                closeCommandPalette(restorePreviousFocus: false),
                .send(.shell(.toggleLeftSidebar))
            )
        case .quit:
            return .concatenate(
                closeCommandPalette(restorePreviousFocus: false),
                .send(.requestApplicationQuit)
            )
        }
    }

    func handleCommandPaletteTextInput(
        _ state: inout State,
        prompt: CommandBarTextPrompt
    ) -> Effect<Action> {
        switch prompt.action {
        case let .addWorktree(projectID):
            guard let project = state.workspace.projects.project(id: projectID) else {
                return setCommandPaletteNotice(CommandBarNotice(
                    text: "Project no longer available.",
                    isError: true
                ))
            }
            guard project.isGitRepository else {
                return setCommandPaletteNotice(CommandBarNotice(
                    text: "Selected project is not a Git repository.",
                    isError: true
                ))
            }

            return .concatenate(
                setCommandPaletteNotice(nil),
                .send(.workspace(.addWorktreeRequested(
                    projectID: projectID,
                    name: state.commandPalette.commandBar.textInput
                )))
            )
        }
    }

    func handleCommandPalettePickerItem(
        _ state: inout State,
        item: CommandBarPickerItem
    ) -> Effect<Action> {
        switch item.payload {
        case let .deleteWorktree(projectID, worktreeID):
            return .concatenate(
                setCommandPaletteNotice(nil),
                .send(.commandPalette(.presentConfirmation(
                    CommandBarConfirmationPrompt(
                    title: "Confirm Delete",
                    message: "Delete worktree '\(item.title)'?",
                    confirmTitle: "Delete Worktree",
                    action: .deleteWorktree(projectID: projectID, worktreeID: worktreeID)
                    ),
                    projectContextID: state.commandPalette.commandBar.projectContextID,
                    workspaceContext: state.commandPalette.commandBar.workspaceContext
                )))
            )
        case let .selectWorkspace(selection):
            return .concatenate(
                setCommandPaletteNotice(nil),
                closeCommandPalette(restorePreviousFocus: false),
                .send(.workspace(.selectWorkspace(selection)))
            )
        case let .createAgent(workspaceSelection, agentName, command):
            guard let workingDirectory = state.workspace.projects.path(for: workspaceSelection) else {
                return setCommandPaletteNotice(CommandBarNotice(
                    text: "Selected workspace has no launch path.",
                    isError: true
                ))
            }
            return .concatenate(
                setCommandPaletteNotice(nil),
                .send(.agent(.launchRequested(AgentLaunchRequest(
                    workspaceSelection: workspaceSelection,
                    workingDirectory: workingDirectory,
                    agentName: agentName,
                    command: command,
                    terminalTheme: state.shell.themeSet.terminalTheme
                ))))
            )
        }
    }

    func handleCommandPaletteConfirmation(
        _ state: inout State,
        prompt: CommandBarConfirmationPrompt
    ) -> Effect<Action> {
        switch prompt.action {
        case let .deleteWorktree(projectID, worktreeID):
            guard let project = state.workspace.projects.project(id: projectID),
                  state.workspace.projects.worktree(id: worktreeID) != nil else {
                return setCommandPaletteNotice(CommandBarNotice(
                    text: "Worktree no longer available.",
                    isError: true
                ))
            }
            guard project.isGitRepository else {
                return setCommandPaletteNotice(CommandBarNotice(
                    text: "Selected project is not a Git repository.",
                    isError: true
                ))
            }
            return .concatenate(
                setCommandPaletteNotice(nil),
                .send(.workspace(.deleteWorktreeRequested(
                    projectID: projectID,
                    worktreeID: worktreeID
                )))
            )
        case let .deleteAgent(sessionID):
            return .concatenate(
                setCommandPaletteNotice(nil),
                closeCommandPalette(restorePreviousFocus: false),
                .send(.agent(.deleteSession(sessionID)))
            )
        case let .removeProject(projectID):
            guard state.workspace.projects.project(id: projectID) != nil else {
                return setCommandPaletteNotice(CommandBarNotice(
                    text: "Project no longer available.",
                    isError: true
                ))
            }
            return .concatenate(
                setCommandPaletteNotice(nil),
                .send(.workspace(.removeProjectRequested(projectID: projectID)))
            )
        }
    }
}

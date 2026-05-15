import ComposableArchitecture
import Foundation

struct WorkspaceFeature: Reducer {
    @Dependency(\.configClient) var configClient
    @Dependency(\.fileSystemClient) var fileSystemClient
    @Dependency(\.gitClient) var gitClient

    @ObservableState
    struct State: Equatable {
        var projects: ProjectsState
    }

    enum Delegate: Equatable {
        case selectionChanged(WorkspaceSelection)
        case inventoryChanged(
            preferredSelection: WorkspaceSelection?,
            revealSidebars: Bool,
            activateMainWindow: Bool
        )
        case configDiagnosticsUpdated(ConfigNotificationState?)
        case workspaceRemoved(Set<WorkspaceSelection>)
        case projectImportCompleted(importedPaths: [String], preferredSelection: WorkspaceSelection?)
        case operationFailed(String)
        case externalOpenFailed(detailMessage: String)
    }

    enum Action: Equatable {
        case refreshRequested(
            preferredSelection: WorkspaceSelection?,
            revealSidebars: Bool,
            activateMainWindow: Bool,
            reportErrors: Bool
        )
        case importRequested([URL], activateMainWindow: Bool)
        case externalOpenRequested(ExternalWorkspaceDeepLinkRequest)
        case addWorktreeRequested(projectID: UUID, name: String)
        case deleteWorktreeRequested(projectID: UUID, worktreeID: UUID)
        case removeProjectRequested(projectID: UUID)
        case selectWorkspace(WorkspaceSelection)
        case toggleProjectCollapse(UUID)
        case toggleSectionCollapse(String)

        case _projectsLoaded(
            ProjectsState,
            preferredSelection: WorkspaceSelection?,
            revealSidebars: Bool,
            activateMainWindow: Bool,
            importedPaths: [String],
            configNotification: ConfigNotificationState?,
            hasConfigDiagnosticsUpdate: Bool
        )
        case delegate(Delegate)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .refreshRequested(preferredSelection, revealSidebars, activateMainWindow, reportErrors):
                let currentProjects = state.projects
                return .run { @MainActor send in
                    do {
                        let loadResult = try await configClient.load()
                        let refreshedProjects = await refreshProjectsState(
                            from: currentProjects,
                            records: loadResult.config.projects,
                            configuredSections: loadResult.config.sections
                        )
                        await send(._projectsLoaded(
                            refreshedProjects,
                            preferredSelection: preferredSelection,
                            revealSidebars: revealSidebars,
                            activateMainWindow: activateMainWindow,
                            importedPaths: [],
                            configNotification: configClient.diagnosticsMessage(
                                loadResult.diagnostics,
                                configClient.configURL()
                            ),
                            hasConfigDiagnosticsUpdate: true
                        ))
                    } catch {
                        if reportErrors {
                            send(.delegate(.operationFailed(error.localizedDescription)))
                        }
                    }
                }

            case let .importRequested(urls, activateMainWindow):
                let currentProjects = state.projects
                return .run { @MainActor send in
                    do {
                        let loadResult = try await configClient.load()
                        let newRecords = importedProjectRecords(
                            from: urls,
                            existingRecords: loadResult.config.projects
                        )
                        guard !newRecords.isEmpty else {
                            return
                        }

                        var fileConfig = loadResult.fileConfig
                        fileConfig.projects = (loadResult.config.projects + newRecords)
                            .map(UserProjectRecord.init(record:))
                        try await configClient.save(fileConfig)

                        let refreshedLoadResult = try await configClient.load()
                        let refreshedProjects = await refreshProjectsState(
                            from: currentProjects,
                            records: refreshedLoadResult.config.projects,
                            configuredSections: refreshedLoadResult.config.sections
                        )
                        let firstImportedPath = normalizePath(newRecords[0].path)
                        let preferredSelection = refreshedProjects.projects.first {
                            normalizePath($0.path) == firstImportedPath
                        }.map { WorkspaceSelection.project($0.id) }

                        await send(._projectsLoaded(
                            refreshedProjects,
                            preferredSelection: preferredSelection,
                            revealSidebars: true,
                            activateMainWindow: activateMainWindow,
                            importedPaths: newRecords.map(\.path),
                            configNotification: configClient.diagnosticsMessage(
                                refreshedLoadResult.diagnostics,
                                configClient.configURL()
                            ),
                            hasConfigDiagnosticsUpdate: true
                        ))
                    } catch {
                        send(.delegate(.operationFailed(error.localizedDescription)))
                    }
                }

            case let .externalOpenRequested(request):
                let normalizedWorkspacePath = normalizePath(request.workspacePath)
                let normalizedProjectPath = normalizePath(request.projectPath)

                if let resolvedSelection = workspaceSelection(
                    matchingNormalizedPath: normalizedWorkspacePath,
                    in: state.projects
                ) {
                    return .merge(
                        .send(.selectWorkspace(resolvedSelection)),
                        .send(.delegate(.inventoryChanged(
                            preferredSelection: resolvedSelection,
                            revealSidebars: false,
                            activateMainWindow: true
                        )))
                    )
                }

                let currentProjects = state.projects
                return .run { @MainActor send in
                    do {
                        let loadResult = try await configClient.load()
                        var refreshedProjects = await refreshProjectsState(
                            from: currentProjects,
                            records: loadResult.config.projects,
                            configuredSections: loadResult.config.sections
                        )
                        var resolvedSelection = workspaceSelection(
                            matchingNormalizedPath: normalizedWorkspacePath,
                            in: refreshedProjects
                        )
                        var importedPaths: [String] = []
                        var diagnostics = loadResult.diagnostics

                        if resolvedSelection == nil {
                            let projectAlreadyConfigured = loadResult.config.projects.contains {
                                normalizePath($0.path) == normalizedProjectPath
                            }

                            if !projectAlreadyConfigured {
                                let newRecords = importedProjectRecords(
                                    from: [URL(fileURLWithPath: normalizedProjectPath, isDirectory: true)],
                                    existingRecords: loadResult.config.projects
                                )
                                if !newRecords.isEmpty {
                                    var fileConfig = loadResult.fileConfig
                                    fileConfig.projects = (loadResult.config.projects + newRecords)
                                        .map(UserProjectRecord.init(record:))
                                    try await configClient.save(fileConfig)

                                    let refreshedLoadResult = try await configClient.load()
                                    refreshedProjects = await refreshProjectsState(
                                        from: currentProjects,
                                        records: refreshedLoadResult.config.projects,
                                        configuredSections: refreshedLoadResult.config.sections
                                    )
                                    importedPaths = newRecords.map(\.path)
                                    diagnostics = refreshedLoadResult.diagnostics
                                }
                            }

                            resolvedSelection = workspaceSelection(
                                matchingNormalizedPath: normalizedWorkspacePath,
                                in: refreshedProjects
                            )
                            if resolvedSelection == nil {
                                resolvedSelection = workspaceSelection(
                                    matchingNormalizedPath: normalizedProjectPath,
                                    in: refreshedProjects
                                )
                            }
                        }

                        guard let resolvedSelection else {
                            send(.delegate(.externalOpenFailed(detailMessage: normalizedWorkspacePath)))
                            return
                        }

                        await send(._projectsLoaded(
                            refreshedProjects,
                            preferredSelection: resolvedSelection,
                            revealSidebars: !importedPaths.isEmpty,
                            activateMainWindow: true,
                            importedPaths: importedPaths,
                            configNotification: configClient.diagnosticsMessage(
                                diagnostics,
                                configClient.configURL()
                            ),
                            hasConfigDiagnosticsUpdate: true
                        ))
                    } catch {
                        send(.delegate(.externalOpenFailed(detailMessage: error.localizedDescription)))
                    }
                }

            case let .addWorktreeRequested(projectID, name):
                guard let project = state.projects.project(id: projectID) else {
                    return .send(.delegate(.operationFailed("Project no longer available.")))
                }
                guard project.isGitRepository else {
                    return .send(.delegate(.operationFailed("Selected project is not a Git repository.")))
                }

                let currentProjects = state.projects
                let records = projectRecords(from: currentProjects)
                let repositoryPath = URL(fileURLWithPath: project.path)
                return .run { @MainActor send in
                    do {
                        let validatedName = try await gitClient.validateWorktreeName(name)
                        let createdWorktree = try await gitClient.createWorktree(
                            repositoryPath,
                            project.name,
                            validatedName
                        )

                        let refreshedProjects = await refreshProjectsState(
                            from: currentProjects,
                            records: records,
                            configuredSections: currentProjects.configuredSections
                        )
                        let preferredSelection = refreshedProjects.projects
                            .flatMap(\.worktrees)
                            .first {
                                normalizePath($0.path) == normalizePath(createdWorktree.path)
                            }
                            .map { WorkspaceSelection.worktree($0.id) }
                        await send(._projectsLoaded(
                            refreshedProjects,
                            preferredSelection: preferredSelection,
                            revealSidebars: false,
                            activateMainWindow: false,
                            importedPaths: [],
                            configNotification: nil,
                            hasConfigDiagnosticsUpdate: false
                        ))
                    } catch {
                        send(.delegate(.operationFailed(error.localizedDescription)))
                    }
                }

            case let .deleteWorktreeRequested(projectID, worktreeID):
                guard let project = state.projects.project(id: projectID),
                      let worktree = state.projects.worktree(id: worktreeID) else {
                    return .send(.delegate(.operationFailed("Worktree no longer available.")))
                }
                guard project.isGitRepository else {
                    return .send(.delegate(.operationFailed("Selected project is not a Git repository.")))
                }

                let currentProjects = state.projects
                let records = projectRecords(from: currentProjects)
                let repositoryPath = URL(fileURLWithPath: project.path)
                let worktreePath = URL(fileURLWithPath: worktree.path)
                return .run { @MainActor send in
                    do {
                        try await gitClient.deleteWorktree(repositoryPath, worktreePath)
                        let refreshedProjects = await refreshProjectsState(
                            from: currentProjects,
                            records: records,
                            configuredSections: currentProjects.configuredSections
                        )
                        await send(._projectsLoaded(
                            refreshedProjects,
                            preferredSelection: .project(projectID),
                            revealSidebars: false,
                            activateMainWindow: false,
                            importedPaths: [],
                            configNotification: nil,
                            hasConfigDiagnosticsUpdate: false
                        ))
                    } catch {
                        send(.delegate(.operationFailed(error.localizedDescription)))
                    }
                }

            case let .removeProjectRequested(projectID):
                guard let project = state.projects.project(id: projectID) else {
                    return .send(.delegate(.operationFailed("Project no longer available.")))
                }

                let normalizedProjectPath = normalizePath(project.path)
                let currentProjects = state.projects
                return .run { @MainActor send in
                    do {
                        let loadResult = try await configClient.load()
                        var fileConfig = loadResult.fileConfig
                        let updatedRecords = loadResult.config.projects.filter {
                            normalizePath($0.path) != normalizedProjectPath
                        }
                        fileConfig.projects = updatedRecords.map(UserProjectRecord.init(record:))
                        try await configClient.save(fileConfig)

                        let refreshedLoadResult = try await configClient.load()
                        let refreshedProjects = await refreshProjectsState(
                            from: currentProjects,
                            records: refreshedLoadResult.config.projects,
                            configuredSections: refreshedLoadResult.config.sections
                        )
                        await send(._projectsLoaded(
                            refreshedProjects,
                            preferredSelection: nil,
                            revealSidebars: false,
                            activateMainWindow: false,
                            importedPaths: [],
                            configNotification: configClient.diagnosticsMessage(
                                refreshedLoadResult.diagnostics,
                                configClient.configURL()
                            ),
                            hasConfigDiagnosticsUpdate: true
                        ))
                    } catch {
                        send(.delegate(.operationFailed(error.localizedDescription)))
                    }
                }

            case let .selectWorkspace(selection):
                guard state.projects.projects.contains(where: { $0.contains(selection) }) else {
                    return .none
                }

                let previousSelection = state.projects.selection
                state.projects.select(selection)
                guard previousSelection != selection else {
                    return .none
                }
                return .send(.delegate(.selectionChanged(selection)))

            case let .toggleProjectCollapse(projectID):
                state.projects.toggleProjectCollapse(projectID)
                return .none

            case let .toggleSectionCollapse(sectionID):
                state.projects.toggleSectionCollapse(sectionID)
                return .none

            case let ._projectsLoaded(
                projects,
                preferredSelection,
                revealSidebars,
                activateMainWindow,
                importedPaths,
                configNotification,
                hasConfigDiagnosticsUpdate
            ):
                let previousProjects = state.projects
                state.projects = projects
                if let preferredSelection,
                   state.projects.projects.contains(where: { $0.contains(preferredSelection) }) {
                    state.projects.select(preferredSelection)
                }

                let previousSelections = Set(previousProjects.orderedNodes.map(\.selection))
                let currentSelections = Set(state.projects.orderedNodes.map(\.selection))
                let removedSelections = previousSelections.subtracting(currentSelections)

                var effects: [Effect<Action>] = [
                    .send(.delegate(.inventoryChanged(
                        preferredSelection: preferredSelection,
                        revealSidebars: revealSidebars,
                        activateMainWindow: activateMainWindow
                    )))
                ]
                if hasConfigDiagnosticsUpdate {
                    effects.append(.send(.delegate(.configDiagnosticsUpdated(configNotification))))
                }

                if previousProjects.selection != state.projects.selection {
                    effects.append(.send(.delegate(.selectionChanged(state.projects.selection))))
                }
                if !removedSelections.isEmpty {
                    effects.append(.send(.delegate(.workspaceRemoved(removedSelections))))
                }
                if !importedPaths.isEmpty {
                    effects.append(.send(.delegate(.projectImportCompleted(
                        importedPaths: importedPaths,
                        preferredSelection: preferredSelection
                    ))))
                }

                return .merge(effects)

            case .delegate:
                return .none
            }
        }
    }
}

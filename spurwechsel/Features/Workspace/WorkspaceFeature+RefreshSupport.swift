import Foundation

extension WorkspaceFeature {
    struct WorkspaceSnapshot {
        let repositoryRootPath: String
        let currentBranch: String?
        let worktrees: [GitWorktreeSnapshot]
    }

    func projectRecords(from projects: ProjectsState) -> [ProjectRecord] {
        projects.projects.map {
            ProjectRecord(path: $0.path, name: $0.name, sections: $0.sectionIDs)
        }
    }

    func refreshProjectsState(
        from currentProjects: ProjectsState,
        records: [ProjectRecord],
        configuredSections: [ProjectSectionRecord]
    ) async -> ProjectsState {
        let existingProjects = currentProjects.projects
        var refreshedProjects: [Project] = []
        let projectIDsByPath = Dictionary(
            uniqueKeysWithValues: existingProjects.map {
                (normalizePath($0.path), $0.id)
            }
        )
        var worktreeIDsByPath = Dictionary(
            uniqueKeysWithValues: existingProjects
                .flatMap { project in
                    project.worktrees.map { worktree in
                        (normalizePath(worktree.path), worktree.id)
                    }
                }
        )

        for record in records {
            let normalizedRecordPath = normalizePath(record.path)
            guard let snapshot = await workspaceSnapshot(at: normalizedRecordPath) else {
                continue
            }

            let existingProject = existingProjects.first(where: {
                $0.id == projectIDsByPath[normalizedRecordPath]
                    || normalizePath($0.path) == normalizedRecordPath
            })
            let projectID = existingProject?.id ?? projectIDsByPath[normalizedRecordPath] ?? UUID()
            let existingWorktreeIDsByPath = Dictionary(
                uniqueKeysWithValues: (existingProject?.worktrees ?? []).map {
                    (normalizePath($0.path), $0.id)
                }
            )

            let discoveredWorktrees = snapshot.worktrees
                .filter { !$0.isPrimary }
                .map { snapshotWorktree -> Worktree in
                    let normalizedWorktreePath = normalizePath(snapshotWorktree.path)
                    let worktreeID = existingWorktreeIDsByPath[normalizedWorktreePath]
                        ?? worktreeIDsByPath[normalizedWorktreePath]
                        ?? UUID()
                    worktreeIDsByPath[normalizedWorktreePath] = worktreeID
                    return Worktree(
                        id: worktreeID,
                        name: snapshotWorktree.name,
                        branch: snapshotWorktree.branch,
                        path: normalizedWorktreePath,
                        isPrimary: false
                    )
                }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

            refreshedProjects.append(
                Project(
                    id: projectID,
                    name: record.displayName,
                    branch: snapshot.currentBranch ?? "",
                    path: snapshot.repositoryRootPath,
                    sectionIDs: record.sections,
                    worktrees: discoveredWorktrees,
                    isGitRepository: snapshot.currentBranch != nil
                )
            )
        }

        var nextProjects = currentProjects
        nextProjects.replaceProjects(
            refreshedProjects,
            configuredSections: configuredSections
        )
        return nextProjects
    }

    func importedProjectRecords(
        from urls: [URL],
        existingRecords: [ProjectRecord]
    ) -> [ProjectRecord] {
        var knownPaths = Set(existingRecords.map { normalizePath($0.path) })
        var newRecords: [ProjectRecord] = []

        for url in urls {
            let normalizedPath = normalizePath(url.path)
            guard fileSystemClient.directoryExists(normalizedPath),
                  !knownPaths.contains(normalizedPath) else {
                continue
            }

            knownPaths.insert(normalizedPath)
            newRecords.append(
                ProjectRecord(
                    path: normalizedPath,
                    name: URL(fileURLWithPath: normalizedPath).lastPathComponent
                )
            )
        }

        return newRecords
    }

    func workspaceSelection(
        matchingNormalizedPath normalizedPath: String,
        in projects: ProjectsState
    ) -> WorkspaceSelection? {
        for project in projects.projects {
            if normalizePath(project.path) == normalizedPath {
                return .project(project.id)
            }
            if let worktree = project.worktrees.first(where: {
                normalizePath($0.path) == normalizedPath
            }) {
                return .worktree(worktree.id)
            }
        }
        return nil
    }

    func workspaceSnapshot(at normalizedPath: String) async -> WorkspaceSnapshot? {
        guard fileSystemClient.directoryExists(normalizedPath) else {
            return nil
        }

        do {
            let snapshot = try await gitClient.repositorySnapshot(URL(fileURLWithPath: normalizedPath))
            return WorkspaceSnapshot(
                repositoryRootPath: snapshot.repositoryRootPath,
                currentBranch: snapshot.currentBranch,
                worktrees: snapshot.worktrees
            )
        } catch let error as GitRepositoryServiceError {
            if case .notRepository = error {
                return WorkspaceSnapshot(
                    repositoryRootPath: normalizedPath,
                    currentBranch: nil,
                    worktrees: []
                )
            }
            return nil
        } catch {
            return nil
        }
    }

    func normalizePath(_ path: String) -> String {
        configClient.normalizeDirectoryPath(URL(fileURLWithPath: path))
    }
}

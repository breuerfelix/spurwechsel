import ComposableArchitecture
import XCTest
@testable import spurwechsel

final class GitWorktreeCommandTests: XCTestCase {
    @MainActor
    func testRefreshProjectsStateMapsGitSnapshotToProjectBranchAndWorktrees() async {
        let repoPath = "/tmp/repo"
        let snapshot = GitRepositorySnapshot(
            repositoryRootPath: repoPath,
            currentBranch: "main",
            worktrees: [
                GitWorktreeSnapshot(name: "repo", path: repoPath, branch: "main", isPrimary: true),
                GitWorktreeSnapshot(name: "feature", path: "\(repoPath)-feature", branch: "feature", isPrimary: false)
            ]
        )
        let feature = makeWorkspaceFeature(
            existingPaths: [repoPath],
            snapshots: [repoPath: snapshot]
        )

        let refreshed = await feature.refreshProjectsState(
            from: ProjectsState.fromImportedProjects([]),
            records: [ProjectRecord(path: repoPath, name: "Repo")],
            configuredSections: []
        )

        XCTAssertEqual(refreshed.projects.count, 1)
        XCTAssertEqual(refreshed.projects.first?.name, "Repo")
        XCTAssertEqual(refreshed.projects.first?.branch, "main")
        XCTAssertEqual(refreshed.projects.first?.worktrees.map(\.branch), ["feature"])
        XCTAssertTrue(refreshed.projects.first?.isGitRepository ?? false)
    }

    @MainActor
    func testRefreshProjectsStateFallsBackToPlainDirectoryForNonRepository() async {
        let plainPath = "/tmp/plain"
        let feature = makeWorkspaceFeature(
            existingPaths: [plainPath],
            nonRepositoryPaths: [plainPath]
        )

        let refreshed = await feature.refreshProjectsState(
            from: ProjectsState.fromImportedProjects([]),
            records: [ProjectRecord(path: plainPath, name: "Plain")],
            configuredSections: []
        )

        XCTAssertEqual(refreshed.projects.count, 1)
        XCTAssertEqual(refreshed.projects.first?.path, plainPath)
        XCTAssertEqual(refreshed.projects.first?.branch, "")
        XCTAssertEqual(refreshed.projects.first?.worktrees.count, 0)
        XCTAssertFalse(refreshed.projects.first?.isGitRepository ?? true)
    }

    @MainActor
    func testRefreshProjectsStateSkipsMissingDirectories() async {
        let feature = makeWorkspaceFeature(existingPaths: [])

        let refreshed = await feature.refreshProjectsState(
            from: ProjectsState.fromImportedProjects([]),
            records: [ProjectRecord(path: "/tmp/missing", name: "Missing")],
            configuredSections: []
        )

        XCTAssertTrue(refreshed.projects.isEmpty)
    }

    @MainActor
    private func makeWorkspaceFeature(
        existingPaths: Set<String>,
        snapshots: [String: GitRepositorySnapshot] = [:],
        nonRepositoryPaths: Set<String> = []
    ) -> WorkspaceFeature {
        withDependencies { dependencies in
            dependencies.configClient.normalizeDirectoryPath = { url in
                url.standardizedFileURL.resolvingSymlinksInPath().path
            }
            dependencies.fileSystemClient.directoryExists = { path in
                existingPaths.contains(path)
            }
            dependencies.gitClient.repositorySnapshot = { url in
                let path = url.standardizedFileURL.resolvingSymlinksInPath().path
                if let snapshot = snapshots[path] {
                    return snapshot
                }
                if nonRepositoryPaths.contains(path) {
                    throw GitRepositoryServiceError.notRepository(path)
                }
                throw NSError(domain: "GitWorktreeCommandTests", code: 1)
            }
        } operation: {
            WorkspaceFeature()
        }
    }
}

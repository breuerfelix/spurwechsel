import XCTest
@testable import spurwechsel

final class GitWorktreeCommandTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("spurwechsel-worktree-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
    }

    @MainActor
    func testStoreMapsGitSnapshotToProjectBranchAndWorktrees() throws {
        let repoPath = temporaryDirectoryURL.appendingPathComponent("repo").path
        let configURL = temporaryDirectoryURL.appendingPathComponent("config.yaml")
        let configStore = ProjectConfigStore(configURL: configURL)
        try configStore.save(
            UserConfigFile.explicit(from: SpurwechselConfig(
                projects: [ProjectRecord(path: repoPath, name: "Repo")]
            ))
        )

        let service = MockGitRepositoryService(
            snapshots: [
                repoPath: GitRepositorySnapshot(
                    repositoryRootPath: repoPath,
                    currentBranch: "main",
                    worktrees: [
                        GitWorktreeSnapshot(name: "repo", path: repoPath, branch: "main", isPrimary: true),
                        GitWorktreeSnapshot(name: "feature", path: "\(repoPath)-feature", branch: "feature", isPrimary: false)
                    ]
                )
            ]
        )

        let store = SpurwechselStore(configStore: configStore, gitService: service)

        XCTAssertEqual(store.projects.projects.count, 1)
        XCTAssertEqual(store.projects.projects.first?.branch, "main")
        XCTAssertEqual(store.projects.projects.first?.worktrees.map(\.branch), ["feature"])
    }

    @MainActor
    func testAddWorktreeCommandTransitionsToTextInput() {
        let project = Project(name: "Repo", branch: "main", path: "/tmp/repo")
        let state = ProjectsState.fromImportedProjects([project])
        let store = SpurwechselStore(
            projects: state,
            gitService: MockGitRepositoryService()
        )

        store.openCommandBar()
        store.executeCommand(.addWorktree, projectContextID: project.id)

        guard case let .textInput(prompt) = store.commandBar.mode else {
            return XCTFail("Expected text input mode")
        }

        XCTAssertEqual(prompt.submitTitle, "Create Worktree")
        XCTAssertEqual(store.commandBar.projectContextID, project.id)
    }

    @MainActor
    func testDeleteWorktreeTransitionsPickerToConfirmation() {
        let worktree = Worktree(name: "feature-a", branch: "feature-a", path: "/tmp/repo-feature")
        let project = Project(name: "Repo", branch: "main", path: "/tmp/repo", worktrees: [worktree])
        let state = ProjectsState.fromImportedProjects([project])
        let store = SpurwechselStore(
            projects: state,
            gitService: MockGitRepositoryService()
        )

        store.openCommandBar()
        store.executeCommand(.deleteWorktree)
        XCTAssertTrue(store.filteredPickerItems.count == 1)

        store.submitCommandBar()
        guard case .confirmation = store.commandBar.mode else {
            return XCTFail("Expected confirmation mode")
        }
    }

    @MainActor
    func testCreateAgentCommandTransitionsToPicker() {
        let project = Project(name: "Repo", branch: "main", path: "/tmp/repo")
        let state = ProjectsState.fromImportedProjects([project])
        let store = SpurwechselStore(
            projects: state,
            gitService: MockGitRepositoryService()
        )

        store.openCommandBar(workspaceContext: .project(project.id))
        store.executeCommand(.createAgent, workspaceContext: .project(project.id))

        guard case let .picker(title, items, _) = store.commandBar.mode else {
            return XCTFail("Expected picker mode")
        }

        XCTAssertEqual(title, "Create Agent")
        XCTAssertEqual(store.commandBar.workspaceContext, .project(project.id))
        XCTAssertTrue(items.contains(where: { $0.title == "claude" }))
    }

    @MainActor
    func testSidebarScopedCreateAgentUsesPassedWorkspace() {
        let projectA = Project(name: "A", branch: "main", path: "/tmp/a")
        let projectB = Project(name: "B", branch: "main", path: "/tmp/b")
        let state = ProjectsState.fromImportedProjects([projectA, projectB])
        let store = SpurwechselStore(
            projects: state,
            gitService: MockGitRepositoryService()
        )

        store.selectWorkspace(.project(projectA.id))
        store.addAgent(to: .project(projectB.id))

        guard case let .picker(_, items, _) = store.commandBar.mode else {
            return XCTFail("Expected picker mode")
        }

        guard let firstPayload = items.first?.payload else {
            return XCTFail("Expected picker items")
        }

        switch firstPayload {
        case let .createAgent(workspaceSelection, _, _):
            XCTAssertEqual(workspaceSelection, .project(projectB.id))
        default:
            XCTFail("Expected create-agent payload")
        }
    }

    @MainActor
    func testDeleteWorktreeKeepsCurrentViewAndCleansDeletedWorkspaceResources() throws {
        let repositoryPath = temporaryDirectoryURL.appendingPathComponent("repo", isDirectory: true).path
        let worktreePath = temporaryDirectoryURL
            .appendingPathComponent("worktrees", isDirectory: true)
            .appendingPathComponent("feature-a", isDirectory: true)
            .path
        let configURL = temporaryDirectoryURL.appendingPathComponent("config.yaml")
        let configStore = ProjectConfigStore(configURL: configURL)
        try configStore.save(
            UserConfigFile.explicit(from: SpurwechselConfig(
                projects: [ProjectRecord(path: repositoryPath, name: "Repo")]
            ))
        )

        let initialSnapshot = GitRepositorySnapshot(
            repositoryRootPath: repositoryPath,
            currentBranch: "main",
            worktrees: [
                GitWorktreeSnapshot(name: "repo", path: repositoryPath, branch: "main", isPrimary: true),
                GitWorktreeSnapshot(name: "feature-a", path: worktreePath, branch: "feature-a", isPrimary: false)
            ]
        )
        let snapshotAfterDelete = GitRepositorySnapshot(
            repositoryRootPath: repositoryPath,
            currentBranch: "main",
            worktrees: [
                GitWorktreeSnapshot(name: "repo", path: repositoryPath, branch: "main", isPrimary: true)
            ]
        )
        let service = MockGitRepositoryService(
            snapshots: [repositoryPath: initialSnapshot]
        )
        service.onDeleteWorktree = { [weak service] _, _ in
            service?.snapshots[repositoryPath] = snapshotAfterDelete
        }

        let store = SpurwechselStore(configStore: configStore, gitService: service)
        guard let project = store.projects.projects.first,
              let worktree = project.worktrees.first
        else {
            return XCTFail("Expected initial project with one worktree")
        }

        let deletedSelection = WorkspaceSelection.worktree(worktree.id)
        let deletedSession = AgentSession(
            workspaceSelection: deletedSelection,
            name: "codex-wt",
            status: .running,
            launcherName: "codex",
            launchCommand: "codex",
            workingDirectory: worktree.path,
            terminalTitle: "codex",
            lastActivity: "now",
            exitCode: nil
        )
        let survivingSession = AgentSession(
            workspaceSelection: .project(project.id),
            name: "codex-root",
            status: .running,
            launcherName: "codex",
            launchCommand: "codex",
            workingDirectory: project.path,
            terminalTitle: "codex",
            lastActivity: "now",
            exitCode: nil
        )
        store.agents.sessions = [deletedSession, survivingSession]
        store.agents.selectedSessionID = deletedSession.id

        store.selectWorkspace(deletedSelection)
        store.selectMainView(.terminal)
        store.selectMainView(.vscode)
        XCTAssertNotNil(store.vscodeWebRuntime(forWorkspaceID: deletedSelection.stableID))

        store.selectMainView(.agent)
        XCTAssertEqual(store.layout.selectedMainView, .agent)

        store.openCommandBar()
        store.executeCommand(.deleteWorktree)
        store.submitCommandBar()
        store.confirmCommandBarAction()

        XCTAssertEqual(store.layout.selectedMainView, .agent)
        XCTAssertEqual(store.projects.selection, .project(project.id))
        XCTAssertEqual(store.surfaceTabs.selectedTab?.mainView, .agent)
        XCTAssertFalse(store.projects.projects.first?.worktrees.contains(where: { $0.id == worktree.id }) ?? true)
        XCTAssertFalse(store.agents.sessions.contains(where: { $0.id == deletedSession.id }))
        XCTAssertTrue(store.agents.sessions.contains(where: { $0.id == survivingSession.id }))
        XCTAssertNil(store.vscodeWebRuntime(forWorkspaceID: deletedSelection.stableID))
        XCTAssertFalse(store.vscodeMountedWorkspaceIDs.contains(deletedSelection.stableID))
        XCTAssertFalse(store.surfaceTabs.tabs.contains(where: { $0.workspaceSelection == deletedSelection }))
    }

    @MainActor
    func testCreateDefaultAgentCommandLaunchesConfiguredDefaultWithoutPicker() throws {
        let projectPath = temporaryDirectoryURL.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: projectPath, withIntermediateDirectories: true)
        let configURL = temporaryDirectoryURL.appendingPathComponent("config.yaml")
        let configStore = ProjectConfigStore(configURL: configURL)
        try configStore.save(
            UserConfigFile.explicit(from: SpurwechselConfig(
                projects: [ProjectRecord(path: projectPath.path, name: "Repo")],
                agents: [
                    AgentConfigRecord(name: "Claude", command: "echo default-agent", isDefault: true),
                    AgentConfigRecord(name: "Codex", command: "echo codex")
                ]
            ))
        )

        let store = SpurwechselStore(
            configStore: configStore,
            gitService: MockGitRepositoryService()
        )
        guard let project = store.projects.projects.first else {
            return XCTFail("Missing project")
        }

        store.openCommandBar(workspaceContext: .project(project.id))
        store.executeCommand(.createDefaultAgent, workspaceContext: .project(project.id))

        XCTAssertFalse(store.commandBar.isPresented)
        XCTAssertEqual(store.agents.sessions.count, 1)
        XCTAssertEqual(store.agents.sessions[0].launcherName, "Claude")
        XCTAssertEqual(store.agents.sessions[0].launchCommand, "echo default-agent")
    }

    func testWorktreeNameValidationRules() throws {
        let service = GitRepositoryService()
        XCTAssertEqual(try service.validateWorktreeName("feature-a"), "feature-a")
        XCTAssertThrowsError(try service.validateWorktreeName(""))
        XCTAssertThrowsError(try service.validateWorktreeName("bad name"))
        XCTAssertThrowsError(try service.validateWorktreeName("../escape"))
    }

    @MainActor
    func testAddAndDeleteWorktreeIntegrationSuccess() throws {
        let repositoryURL = try createGitRepository(named: "repo")
        let configStore = ProjectConfigStore(configURL: temporaryDirectoryURL.appendingPathComponent("config.yaml"))
        try configStore.save(
            UserConfigFile.explicit(from: SpurwechselConfig(
                projects: [ProjectRecord(path: repositoryURL.path, name: "Repo")]
            ))
        )

        let worktreeRoot = temporaryDirectoryURL.appendingPathComponent("worktrees", isDirectory: true).path
        let service = GitRepositoryService(
            environment: ["SPURWECHSEL_WORKTREES_ROOT": worktreeRoot]
        )
        let store = SpurwechselStore(configStore: configStore, gitService: service)
        guard let project = store.projects.projects.first else {
            return XCTFail("Missing project")
        }

        store.addWorktree(to: project.id)
        store.updateCommandTextInput("feature-a")
        store.submitCommandBar()

        guard let createdWorktree = store.projects.projects.first?.worktrees.first(where: { $0.branch == "feature-a" }) else {
            return XCTFail("Missing created worktree")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: createdWorktree.path))

        store.openCommandBar()
        store.executeCommand(.deleteWorktree)
        store.submitCommandBar()
        store.confirmCommandBarAction()

        XCTAssertFalse(store.projects.projects.first?.worktrees.contains(where: { $0.branch == "feature-a" }) ?? true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: createdWorktree.path))
    }

    @MainActor
    func testAddWorktreeUsesIncrementedBranchWhenRequestedBranchExists() throws {
        let repositoryURL = try createGitRepository(named: "repo")
        try runGit(arguments: ["branch", "feature-a"], in: repositoryURL)

        let configStore = ProjectConfigStore(configURL: temporaryDirectoryURL.appendingPathComponent("config.yaml"))
        try configStore.save(
            UserConfigFile.explicit(from: SpurwechselConfig(
                projects: [ProjectRecord(path: repositoryURL.path, name: "Repo")]
            ))
        )

        let worktreeRoot = temporaryDirectoryURL.appendingPathComponent("worktrees", isDirectory: true).path
        let service = GitRepositoryService(
            environment: ["SPURWECHSEL_WORKTREES_ROOT": worktreeRoot]
        )
        let store = SpurwechselStore(configStore: configStore, gitService: service)
        guard let project = store.projects.projects.first else {
            return XCTFail("Missing project")
        }

        store.addWorktree(to: project.id)
        store.updateCommandTextInput("feature-a")
        store.submitCommandBar()

        guard let createdWorktree = store.projects.projects.first?.worktrees.first(where: { $0.name == "feature-a" }) else {
            return XCTFail("Missing created worktree")
        }
        XCTAssertEqual(createdWorktree.branch, "feature-a-0")
        XCTAssertTrue(createdWorktree.path.hasSuffix("/feature-a"))

        let worktreeBranch = try runGitCapture(arguments: ["branch", "--show-current"], in: URL(fileURLWithPath: createdWorktree.path))
        XCTAssertEqual(worktreeBranch, "feature-a-0")
    }

    @MainActor
    func testAddWorktreeUsesNextIncrementedBranchForMultipleCollisions() throws {
        let repositoryURL = try createGitRepository(named: "repo")
        try runGit(arguments: ["branch", "feature-a"], in: repositoryURL)
        try runGit(arguments: ["branch", "feature-a-0"], in: repositoryURL)
        try runGit(arguments: ["branch", "feature-a-1"], in: repositoryURL)

        let configStore = ProjectConfigStore(configURL: temporaryDirectoryURL.appendingPathComponent("config.yaml"))
        try configStore.save(
            UserConfigFile.explicit(from: SpurwechselConfig(
                projects: [ProjectRecord(path: repositoryURL.path, name: "Repo")]
            ))
        )

        let worktreeRoot = temporaryDirectoryURL.appendingPathComponent("worktrees", isDirectory: true).path
        let service = GitRepositoryService(
            environment: ["SPURWECHSEL_WORKTREES_ROOT": worktreeRoot]
        )
        let store = SpurwechselStore(configStore: configStore, gitService: service)
        guard let project = store.projects.projects.first else {
            return XCTFail("Missing project")
        }

        store.addWorktree(to: project.id)
        store.updateCommandTextInput("feature-a")
        store.submitCommandBar()

        guard let createdWorktree = store.projects.projects.first?.worktrees.first(where: { $0.name == "feature-a" }) else {
            return XCTFail("Missing created worktree")
        }
        XCTAssertEqual(createdWorktree.branch, "feature-a-2")
    }

    @MainActor
    func testAddWorktreeFailureShowsErrorNotice() {
        let project = Project(name: "Repo", branch: "main", path: "/tmp/repo")
        let state = ProjectsState.fromImportedProjects([project])
        let service = MockGitRepositoryService()
        service.validateError = GitRepositoryServiceError.invalidWorktreeName("bad name")

        let store = SpurwechselStore(projects: state, gitService: service)
        store.addWorktree(to: project.id)
        store.updateCommandTextInput("bad name")
        store.submitCommandBar()

        XCTAssertTrue(store.commandBar.notice?.isError == true)
    }

    @MainActor
    func testDeleteWorktreeFailureShowsErrorNotice() {
        let worktree = Worktree(name: "feature-a", branch: "feature-a", path: "/tmp/repo-feature")
        let project = Project(name: "Repo", branch: "main", path: "/tmp/repo", worktrees: [worktree])
        let state = ProjectsState.fromImportedProjects([project])
        let service = MockGitRepositoryService()
        service.deleteError = GitRepositoryServiceError.commandFailed("boom")

        let store = SpurwechselStore(projects: state, gitService: service)
        store.openCommandBar()
        store.executeCommand(.deleteWorktree)
        store.submitCommandBar()
        store.confirmCommandBarAction()

        XCTAssertTrue(store.commandBar.notice?.isError == true)
    }

    private func createGitRepository(named name: String) throws -> URL {
        let repositoryURL = temporaryDirectoryURL.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)

        try runGit(arguments: ["init", "--initial-branch", "main"], in: repositoryURL)
        try runGit(arguments: ["config", "user.name", "Spurwechsel Tests"], in: repositoryURL)
        try runGit(arguments: ["config", "user.email", "tests@example.com"], in: repositoryURL)

        let fileURL = repositoryURL.appendingPathComponent("README.md")
        try "seed".write(to: fileURL, atomically: true, encoding: .utf8)
        try runGit(arguments: ["add", "README.md"], in: repositoryURL)
        try runGit(arguments: ["commit", "-m", "seed"], in: repositoryURL)

        return repositoryURL
    }

    private func runGit(arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = directory

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: stderrData, encoding: .utf8) ?? "git command failed"
            XCTFail(message)
            throw NSError(domain: "GitWorktreeCommandTests", code: Int(process.terminationStatus))
        }
    }

    private func runGitCapture(arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = directory

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: stderrData, encoding: .utf8) ?? "git command failed"
            XCTFail(message)
            throw NSError(domain: "GitWorktreeCommandTests", code: Int(process.terminationStatus))
        }

        return String(data: stdout, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

private final class MockGitRepositoryService: GitRepositoryServicing {
    var snapshots: [String: GitRepositorySnapshot]
    var validateError: Error?
    var createError: Error?
    var deleteError: Error?
    var onDeleteWorktree: ((URL, URL) -> Void)?

    init(snapshots: [String: GitRepositorySnapshot] = [:]) {
        self.snapshots = snapshots
    }

    func repositorySnapshot(at path: URL) throws -> GitRepositorySnapshot {
        let normalizedPath = path.standardizedFileURL.resolvingSymlinksInPath().path
        if let snapshot = snapshots[normalizedPath] ?? snapshots[path.path] {
            return snapshot
        }
        throw GitRepositoryServiceError.notRepository(path.path)
    }

    func createWorktree(repositoryPath: URL, projectName: String, worktreeName: String) throws -> GitWorktreeSnapshot {
        if let createError {
            throw createError
        }
        return GitWorktreeSnapshot(
            name: worktreeName,
            path: "/tmp/\(projectName)-\(worktreeName)",
            branch: worktreeName,
            isPrimary: false
        )
    }

    func deleteWorktree(repositoryPath: URL, worktreePath: URL) throws {
        if let deleteError {
            throw deleteError
        }
        onDeleteWorktree?(repositoryPath, worktreePath)
    }

    func validateWorktreeName(_ name: String) throws -> String {
        if let validateError {
            throw validateError
        }
        return name
    }
}

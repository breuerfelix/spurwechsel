import ComposableArchitecture
import XCTest
@testable import spurwechsel

@MainActor
final class AppFeatureIntegrationTests: XCTestCase {
    func testWorkspaceRemovalPropagatesToAgentAndEditorFeatures() async {
        let runtime = AppRuntime()
        var state = AppBootstrap.makeInitialState(runtime: runtime)
        state.workspace.projects = PreviewFixtures.projectsState

        let removedSelection = WorkspaceSelection.project(PreviewFixtures.tiltrunProject.id)
        let keptSelection = WorkspaceSelection.project(PreviewFixtures.orbitProject.id)

        let removedSession = AgentSession(
            workspaceSelection: removedSelection,
            name: "opencode-1",
            status: .running,
            launcherName: "opencode",
            launchCommand: "opencode",
            workingDirectory: "/tmp/tiltrun",
            terminalTitle: "opencode",
            lastActivity: "now",
            exitCode: nil
        )
        let keptSession = AgentSession(
            workspaceSelection: keptSelection,
            name: "codex-2",
            status: .running,
            launcherName: "codex",
            launchCommand: "codex",
            workingDirectory: "/tmp/orbit",
            terminalTitle: "codex",
            lastActivity: "now",
            exitCode: nil
        )

        state.agent.agents = AgentState(
            sessions: [removedSession, keptSession],
            selectedSessionID: removedSession.id,
            nextAgentCount: 3
        )
        state.editor.sessionsByWorkspaceID = [
            removedSelection.stableID: EditorSessionState(
                workspaceSelectionID: removedSelection.stableID,
                workspaceName: "TiltRun",
                workspacePath: "/tmp/tiltrun",
                serverAddress: "http://127.0.0.1:19001/",
                workspaceAddress: "http://127.0.0.1:19001/?folder=/tmp/tiltrun",
                status: .running,
                statusMessage: "running",
                errorMessage: nil,
                lastOutputLine: nil
            ),
            keptSelection.stableID: EditorSessionState(
                workspaceSelectionID: keptSelection.stableID,
                workspaceName: "Orbit",
                workspacePath: "/tmp/orbit",
                serverAddress: "http://127.0.0.1:19002/",
                workspaceAddress: "http://127.0.0.1:19002/?folder=/tmp/orbit",
                status: .running,
                statusMessage: "running",
                errorMessage: nil,
                lastOutputLine: nil
            )
        ]
        state.editor.selectedWorkspaceID = removedSelection.stableID

        let store = TestStore(initialState: state) {
            AppFeature()
        } withDependencies: { dependencies in
            dependencies.terminalRegistryClient.acquireAgentController = { _, _, _, _, _, _, _, _ in }
            dependencies.terminalRegistryClient.releaseAgentController = { _ in }
            dependencies.terminalRegistryClient.setAgentAttached = { _, _ in }
            dependencies.terminalRegistryClient.setWorkspaceAttached = { _, _ in }
            dependencies.terminalRegistryClient.ensureWorkspaceController = { _, _, _ in }
            dependencies.terminalRegistryClient.shutdownAll = { _, _ in
                TerminalRegistryShutdownSummary(sessionCount: 0, forcedKillCount: 0, timedOutCount: 0)
            }
            dependencies.vscodeRuntimeClient.removeBrowserRuntime = { _ in }
            dependencies.vscodeRuntimeClient.syncBrowserRuntimeCache = { _ in }
            dependencies.vscodeRuntimeClient.invalidateBrowserAddresses = {}
            dependencies.vscodeRuntimeClient.stop = {}
            dependencies.vscodeRuntimeClient.start = { _, _, _ in }
            dependencies.vscodeRuntimeClient.shutdown = { _, _ in
                VSCodeServerShutdownSummary(didForceKill: false, didTimeout: false)
            }
            dependencies.vscodeRuntimeClient.loadWorkspaceInBrowser = { _, _, _ in false }
        }

        await store.send(.workspace(.delegate(.workspaceRemoved([removedSelection]))))

        await store.receive(.agent(.workspacesRemoved([removedSelection]))) {
            XCTAssertEqual($0.agent.agents.sessions.map(\.id), [keptSession.id])
            XCTAssertEqual($0.agent.agents.selectedSessionID, keptSession.id)
        }

        await store.receive(.editor(.workspacesRemoved([removedSelection.stableID]))) {
            XCTAssertNil($0.editor.sessionsByWorkspaceID[removedSelection.stableID])
            XCTAssertEqual($0.editor.sessionsByWorkspaceID[keptSelection.stableID]?.workspaceName, "Orbit")
        }
    }

    func testInvokeCommandCreateAgentPresentsPickerDirectly() async {
        let runtime = AppRuntime()
        var state = AppBootstrap.makeInitialState(runtime: runtime)
        let project = Project(name: "Repo", branch: "main", path: "/tmp/repo")
        state.workspace.projects = ProjectsState.fromImportedProjects([project])

        let config = SpurwechselConfig(
            agents: [AgentConfigRecord(name: "alpha", command: "alpha --fast", isDefault: true)]
        )
        let loadResult = ConfigLoadResult(
            fileConfig: .explicit(from: config),
            config: config,
            diagnostics: []
        )
        let expectedItem = CommandBarPickerItem(
            id: "agent-alpha",
            title: "alpha",
            subtitle: "alpha --fast",
            symbolName: "sparkles.rectangle.stack",
            payload: .createAgent(
                workspaceSelection: .project(project.id),
                agentName: "alpha",
                command: "alpha --fast"
            )
        )

        let store = TestStore(initialState: state) {
            AppFeature()
        } withDependencies: { dependencies in
            dependencies.configClient.load = {
                loadResult
            }
        }

        await store.send(.invokeCommand(
            .createAgent,
            projectContextID: nil,
            workspaceContext: .project(project.id)
        ))

        await store.receive(.commandPalette(.presentPicker(
            title: "Create Agent",
            items: [expectedItem],
            emptyMessage: "No agents configured.",
            projectContextID: nil,
            workspaceContext: .project(project.id)
        ))) {
            $0.commandPalette.commandBar.isPresented = true
            $0.commandPalette.commandBar.mode = .picker(
                title: "Create Agent",
                items: [expectedItem],
                emptyMessage: "No agents configured."
            )
            $0.commandPalette.commandBar.projectContextID = nil
            $0.commandPalette.commandBar.workspaceContext = .project(project.id)
            $0.commandPalette.commandBar.notice = nil
            $0.commandPalette.commandBar.query = ""
            $0.commandPalette.commandBar.highlightedIndex = 0
        }
    }

    func testInvokeCommandAddWorktreePresentsPromptDirectly() async {
        let runtime = AppRuntime()
        var state = AppBootstrap.makeInitialState(runtime: runtime)
        let project = Project(name: "Repo", branch: "main", path: "/tmp/repo")
        state.workspace.projects = ProjectsState.fromImportedProjects([project])

        let expectedPrompt = CommandBarTextPrompt(
            title: "Add Worktree (Repo)",
            placeholder: "Enter worktree name",
            submitTitle: "Create Worktree",
            action: .addWorktree(projectID: project.id)
        )

        let store = TestStore(initialState: state) {
            AppFeature()
        }

        await store.send(.invokeCommand(
            .addWorktree,
            projectContextID: project.id,
            workspaceContext: nil
        ))

        await store.receive(.commandPalette(.presentTextInput(
            expectedPrompt,
            projectContextID: project.id,
            workspaceContext: nil
        ))) {
            $0.commandPalette.commandBar.isPresented = true
            $0.commandPalette.commandBar.mode = .textInput(expectedPrompt)
            $0.commandPalette.commandBar.projectContextID = project.id
            $0.commandPalette.commandBar.workspaceContext = nil
            $0.commandPalette.commandBar.textInput = ""
            $0.commandPalette.commandBar.notice = nil
            $0.commandPalette.commandBar.query = ""
            $0.commandPalette.commandBar.highlightedIndex = 0
        }
    }
}

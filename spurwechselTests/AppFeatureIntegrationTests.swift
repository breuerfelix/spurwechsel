import ComposableArchitecture
import XCTest
@testable import spurwechsel

@MainActor
final class AppFeatureIntegrationTests: XCTestCase {
    func testToggleVoiceInputStartsForVisibleAgentSession() async {
        let runtime = AppRuntime()
        var state = AppBootstrap.makeInitialState(runtime: runtime)
        let session = makeSession(
            name: "codex-voice",
            workspaceSelection: .project(PreviewFixtures.tiltrunProject.id)
        )
        state = stateWithVisibleAgentSession(state, session: session)

        let store = TestStore(initialState: state) {
            AppFeature()
        } withDependencies: { dependencies in
            dependencies.voiceInputClient.start = { _ in
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
            dependencies.voiceInputClient.stop = {}
            dependencies.terminalRegistryClient.agentController = { _ in nil }
            dependencies.terminalRegistryClient.workspaceController = { workspaceID, workingDirectory, terminalTheme in
                runtime.workspaceTerminalController(
                    workspaceID: workspaceID,
                    workingDirectory: workingDirectory,
                    terminalTheme: terminalTheme
                )
            }
            dependencies.terminalRegistryClient.workspaceControllerIfLoaded = { workspaceID in
                runtime.workspaceTerminalControllerIfLoaded(workspaceID: workspaceID)
            }
            dependencies.terminalRegistryClient.releaseAgentController = { _ in }
            dependencies.terminalRegistryClient.setAgentAttached = { _, _ in }
            dependencies.terminalRegistryClient.setWorkspaceAttached = { _, _ in }
            dependencies.terminalRegistryClient.shutdownAll = { _, _ in
                TerminalRegistryShutdownSummary(sessionCount: 0, forcedKillCount: 0, timedOutCount: 0)
            }
        }
        await store.send(.toggleVoiceInput) {
            $0.voiceInput.activeSessionID = session.id
            $0.voiceInput.hasInsertedText = false
        }
    }

    func testVoiceInputStopsWhenLeavingAgentView() async {
        let runtime = AppRuntime()
        var state = AppBootstrap.makeInitialState(runtime: runtime)
        let session = makeSession(
            name: "codex-voice",
            workspaceSelection: .project(PreviewFixtures.tiltrunProject.id)
        )
        state = stateWithVisibleAgentSession(state, session: session)

        var streamContinuation: AsyncStream<VoiceInputEvent>.Continuation?
        let store = TestStore(initialState: state) {
            AppFeature()
        } withDependencies: { dependencies in
            dependencies.voiceInputClient.start = { _ in
                AsyncStream { continuation in
                    streamContinuation = continuation
                }
            }
            dependencies.voiceInputClient.stop = {
                streamContinuation?.yield(.stopped)
                streamContinuation?.finish()
            }
            dependencies.terminalRegistryClient.agentController = { _ in nil }
            dependencies.terminalRegistryClient.workspaceController = { workspaceID, workingDirectory, terminalTheme in
                runtime.workspaceTerminalController(
                    workspaceID: workspaceID,
                    workingDirectory: workingDirectory,
                    terminalTheme: terminalTheme
                )
            }
            dependencies.terminalRegistryClient.workspaceControllerIfLoaded = { workspaceID in
                runtime.workspaceTerminalControllerIfLoaded(workspaceID: workspaceID)
            }
            dependencies.terminalRegistryClient.releaseAgentController = { _ in }
            dependencies.terminalRegistryClient.setAgentAttached = { _, _ in }
            dependencies.terminalRegistryClient.setWorkspaceAttached = { _, _ in }
            dependencies.terminalRegistryClient.shutdownAll = { _, _ in
                TerminalRegistryShutdownSummary(sessionCount: 0, forcedKillCount: 0, timedOutCount: 0)
            }
        }
        store.exhaustivity = .off

        await store.send(.toggleVoiceInput) {
            $0.voiceInput.activeSessionID = session.id
            $0.voiceInput.hasInsertedText = false
        }
        await store.send(.shell(.selectMainView(.terminal)))
        await store.receive {
            guard case .stopVoiceInput = $0 else {
                return false
            }
            return true
        }
        await store.receive {
            guard case .voiceInputEvent(.stopped) = $0 else {
                return false
            }
            return true
        } assert: {
            $0.voiceInput.activeSessionID = nil
            $0.voiceInput.hasInsertedText = false
        }
    }

    func testVoiceInputStopsWhenLaunchingNewAgentSession() async {
        let runtime = AppRuntime()
        var state = AppBootstrap.makeInitialState(runtime: runtime)
        let workspaceSelection = WorkspaceSelection.project(PreviewFixtures.tiltrunProject.id)
        let oldSession = makeSession(name: "codex-old", workspaceSelection: workspaceSelection)
        let newSession = makeSession(name: "codex-new", workspaceSelection: workspaceSelection)
        state.agent.agents = AgentState(
            sessions: [oldSession, newSession],
            selectedSessionID: newSession.id,
            nextAgentCount: 3
        )
        let oldTab = SurfaceTab(
            id: .agentSession(oldSession.id),
            title: oldSession.name,
            workspaceSelection: workspaceSelection,
            sessionID: oldSession.id
        )
        state.workbench.surfaceTabs.tabs = [oldTab]
        state.workbench.surfaceTabs.selectedTabID = oldTab.id
        state.workbench.surfaceMountState.mount(oldTab.id, in: .main)
        state.shell.layout.selectedMainView = .agent

        var streamContinuation: AsyncStream<VoiceInputEvent>.Continuation?
        let store = TestStore(initialState: state) {
            AppFeature()
        } withDependencies: { dependencies in
            dependencies.voiceInputClient.start = { _ in
                AsyncStream { continuation in
                    streamContinuation = continuation
                }
            }
            dependencies.voiceInputClient.stop = {
                streamContinuation?.yield(.stopped)
                streamContinuation?.finish()
            }
            dependencies.terminalRegistryClient.agentController = { _ in nil }
            dependencies.terminalRegistryClient.workspaceController = { workspaceID, workingDirectory, terminalTheme in
                runtime.workspaceTerminalController(
                    workspaceID: workspaceID,
                    workingDirectory: workingDirectory,
                    terminalTheme: terminalTheme
                )
            }
            dependencies.terminalRegistryClient.workspaceControllerIfLoaded = { workspaceID in
                runtime.workspaceTerminalControllerIfLoaded(workspaceID: workspaceID)
            }
            dependencies.terminalRegistryClient.releaseAgentController = { _ in }
            dependencies.terminalRegistryClient.setAgentAttached = { _, _ in }
            dependencies.terminalRegistryClient.setWorkspaceAttached = { _, _ in }
            dependencies.terminalRegistryClient.shutdownAll = { _, _ in
                TerminalRegistryShutdownSummary(sessionCount: 0, forcedKillCount: 0, timedOutCount: 0)
            }
        }
        store.exhaustivity = .off

        await store.send(.toggleVoiceInput) {
            $0.voiceInput.activeSessionID = oldSession.id
            $0.voiceInput.hasInsertedText = false
        }

        await store.send(.agent(.delegate(.sessionLaunched(
            sessionID: newSession.id,
            workspaceSelection: workspaceSelection
        ))))
        await store.receive {
            guard case .stopVoiceInput = $0 else {
                return false
            }
            return true
        }
        await store.receive {
            guard case .voiceInputEvent(.stopped) = $0 else {
                return false
            }
            return true
        } assert: {
            $0.voiceInput.activeSessionID = nil
            $0.voiceInput.hasInsertedText = false
        }
    }

    func testVoiceInputStopFlushesTranscriptBeforeClearingState() async {
        let runtime = AppRuntime()
        var state = AppBootstrap.makeInitialState(runtime: runtime)
        let session = makeSession(
            name: "codex-voice",
            workspaceSelection: .project(PreviewFixtures.tiltrunProject.id)
        )
        state = stateWithVisibleAgentSession(state, session: session)

        var streamContinuation: AsyncStream<VoiceInputEvent>.Continuation?
        let store = TestStore(initialState: state) {
            AppFeature()
        } withDependencies: { dependencies in
            dependencies.voiceInputClient.start = { _ in
                AsyncStream { continuation in
                    streamContinuation = continuation
                }
            }
            dependencies.voiceInputClient.stop = {
                streamContinuation?.yield(.transcriptDelta("hello world", isFinal: true))
                streamContinuation?.yield(.stopped)
                streamContinuation?.finish()
            }
            dependencies.terminalRegistryClient.agentController = { _ in nil }
            dependencies.terminalRegistryClient.workspaceController = { workspaceID, workingDirectory, terminalTheme in
                runtime.workspaceTerminalController(
                    workspaceID: workspaceID,
                    workingDirectory: workingDirectory,
                    terminalTheme: terminalTheme
                )
            }
            dependencies.terminalRegistryClient.workspaceControllerIfLoaded = { workspaceID in
                runtime.workspaceTerminalControllerIfLoaded(workspaceID: workspaceID)
            }
            dependencies.terminalRegistryClient.releaseAgentController = { _ in }
            dependencies.terminalRegistryClient.setAgentAttached = { _, _ in }
            dependencies.terminalRegistryClient.setWorkspaceAttached = { _, _ in }
            dependencies.terminalRegistryClient.shutdownAll = { _, _ in
                TerminalRegistryShutdownSummary(sessionCount: 0, forcedKillCount: 0, timedOutCount: 0)
            }
        }
        store.exhaustivity = .off

        await store.send(.toggleVoiceInput) {
            $0.voiceInput.activeSessionID = session.id
            $0.voiceInput.hasInsertedText = false
        }

        await store.send(.stopVoiceInput)
        await store.receive {
            guard case let .voiceInputEvent(.transcriptDelta(text, isFinal)) = $0 else {
                return false
            }
            return text == "hello world" && isFinal
        } assert: {
            $0.voiceInput.hasInsertedText = true
        }
        await store.receive {
            guard case .voiceInputEvent(.stopped) = $0 else {
                return false
            }
            return true
        } assert: {
            $0.voiceInput.activeSessionID = nil
            $0.voiceInput.hasInsertedText = false
        }
    }

    func testVoiceInputTranscriptDoesNotCrashWhenControllerMissing() async {
        let runtime = AppRuntime()
        var state = AppBootstrap.makeInitialState(runtime: runtime)
        let session = makeSession(
            name: "codex-voice",
            workspaceSelection: .project(PreviewFixtures.tiltrunProject.id)
        )
        state = stateWithVisibleAgentSession(state, session: session)
        state.voiceInput.activeSessionID = session.id

        let store = TestStore(initialState: state) {
            AppFeature()
        } withDependencies: { dependencies in
            dependencies.voiceInputClient.start = { _ in
                AsyncStream { $0.finish() }
            }
            dependencies.voiceInputClient.stop = {}
            dependencies.terminalRegistryClient.agentController = { _ in nil }
            dependencies.terminalRegistryClient.workspaceController = { workspaceID, workingDirectory, terminalTheme in
                runtime.workspaceTerminalController(
                    workspaceID: workspaceID,
                    workingDirectory: workingDirectory,
                    terminalTheme: terminalTheme
                )
            }
            dependencies.terminalRegistryClient.workspaceControllerIfLoaded = { workspaceID in
                runtime.workspaceTerminalControllerIfLoaded(workspaceID: workspaceID)
            }
            dependencies.terminalRegistryClient.releaseAgentController = { _ in }
            dependencies.terminalRegistryClient.setAgentAttached = { _, _ in }
            dependencies.terminalRegistryClient.setWorkspaceAttached = { _, _ in }
            dependencies.terminalRegistryClient.shutdownAll = { _, _ in
                TerminalRegistryShutdownSummary(sessionCount: 0, forcedKillCount: 0, timedOutCount: 0)
            }
        }
        await store.send(.voiceInputEvent(.transcriptDelta("hello", isFinal: false))) {
            $0.voiceInput.hasInsertedText = true
        }
    }

    func testVoiceInputAppendableDeltaReturnsSuffixWhenAppendable() {
        XCTAssertEqual(
            voiceInputAppendableDelta(previous: "hello", current: "hello world"),
            " world"
        )
    }

    func testVoiceInputAppendableDeltaReturnsNilWhenNonAppendable() {
        XCTAssertNil(
            voiceInputAppendableDelta(previous: "hello world", current: "hello brave world")
        )
    }

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
            dependencies.terminalRegistryClient.workspaceController = { workspaceID, workingDirectory, terminalTheme in
                runtime.workspaceTerminalController(
                    workspaceID: workspaceID,
                    workingDirectory: workingDirectory,
                    terminalTheme: terminalTheme
                )
            }
            dependencies.terminalRegistryClient.workspaceControllerIfLoaded = { workspaceID in
                runtime.workspaceTerminalControllerIfLoaded(workspaceID: workspaceID)
            }
            dependencies.terminalRegistryClient.releaseAgentController = { _ in }
            dependencies.terminalRegistryClient.setAgentAttached = { _, _ in }
            dependencies.terminalRegistryClient.setWorkspaceAttached = { _, _ in }
            dependencies.vscodeRuntimeClient.removeBrowserRuntime = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.workspace(.delegate(.workspaceRemoved([removedSelection]))))

        await store.receive {
            guard case let .agent(.workspacesRemoved(selections)) = $0 else {
                return false
            }
            return selections == [removedSelection]
        } assert: {
            XCTAssertEqual($0.agent.agents.sessions.map(\.id), [keptSession.id])
            XCTAssertEqual($0.agent.agents.selectedSessionID, keptSession.id)
        }

        await store.receive {
            guard case let .editor(.workspacesRemoved(workspaceIDs)) = $0 else {
                return false
            }
            return workspaceIDs == [removedSelection.stableID]
        } assert: {
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
        store.exhaustivity = .off

        await store.send(.invokeCommand(
            .createAgent,
            projectContextID: nil,
            workspaceContext: .project(project.id)
        ))

        await store.receive {
            guard case let .commandPalette(.presentPicker(
                title,
                items,
                emptyMessage,
                projectContextID,
                workspaceContext
            )) = $0 else {
                return false
            }
            return title == "Create Agent"
                && items == [expectedItem]
                && emptyMessage == "No agents configured."
                && projectContextID == nil
                && workspaceContext == .project(project.id)
        } assert: {
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
        store.exhaustivity = .off

        await store.send(.invokeCommand(
            .addWorktree,
            projectContextID: project.id,
            workspaceContext: nil
        ))

        await store.receive {
            guard case let .commandPalette(.presentTextInput(
                prompt,
                projectContextID,
                workspaceContext
            )) = $0 else {
                return false
            }
            return prompt == expectedPrompt
                && projectContextID == project.id
                && workspaceContext == nil
        } assert: {
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

private extension AppFeatureIntegrationTests {
    func makeSession(
        name: String,
        workspaceSelection: WorkspaceSelection
    ) -> AgentSession {
        AgentSession(
            workspaceSelection: workspaceSelection,
            name: name,
            status: .running,
            launcherName: "codex",
            launchCommand: "codex",
            workingDirectory: "/tmp/\(name)",
            terminalTitle: "codex",
            lastActivity: "now",
            exitCode: nil
        )
    }

    func stateWithVisibleAgentSession(
        _ state: AppFeature.State,
        session: AgentSession
    ) -> AppFeature.State {
        var state = state
        state.agent.agents = AgentState(
            sessions: [session],
            selectedSessionID: session.id,
            nextAgentCount: 2
        )
        let tab = SurfaceTab(
            id: .agentSession(session.id),
            title: session.name,
            workspaceSelection: session.workspaceSelection,
            sessionID: session.id
        )
        state.workbench.surfaceTabs.tabs = [tab]
        state.workbench.surfaceTabs.selectedTabID = tab.id
        state.workbench.surfaceMountState.mount(tab.id, in: .main)
        state.shell.layout.selectedMainView = .agent
        return state
    }

}

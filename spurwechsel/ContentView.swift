import ComposableArchitecture
import SwiftUI

struct ContentView: View {
    let store: StoreOf<AppFeature>
    let composition: AppComposition

    init(
        store: StoreOf<AppFeature>,
        composition: AppComposition
    ) {
        self.store = store
        self.composition = composition
    }

    var body: some View {
        AppView(store: store)
            .environment(\.shellSceneBridge, composition.shellSceneBridge)
    }
}

struct ContentView_Previews: PreviewProvider {
    @MainActor
    static var previews: some View {
        Group {
            previewContentView(mainView: .agent)
                .previewDisplayName("Dark / Agent Compact")

            previewContentView(mainView: .terminal)
                .previewDisplayName("Dark / Terminal")

            previewContentView(mainView: .vscode, vscodeSession: PreviewFixtures.vscodeIdleState)
                .previewDisplayName("Dark / VSCode Idle")

            previewContentView(mainView: .vscode, vscodeSession: PreviewFixtures.vscodeStartingState)
                .previewDisplayName("Dark / VSCode Starting")

            previewContentView(mainView: .vscode, vscodeSession: PreviewFixtures.vscodeRunningState)
                .previewDisplayName("Dark / VSCode Running")

            previewContentView(mainView: .vscode, vscodeSession: PreviewFixtures.vscodeStoppedState)
                .previewDisplayName("Dark / VSCode Stopped")

            previewContentView(mainView: .vscode, vscodeSession: PreviewFixtures.vscodeFailureState)
                .previewDisplayName("Dark / VSCode Failure")
        }
        .frame(width: 1560, height: 940)
    }

    @MainActor
    private static func previewContentView(
        mainView: MainViewKind,
        vscodeSession: EditorSessionState? = nil
    ) -> ContentView {
        let runtime = AppRuntime()
        var state = AppBootstrap.makeInitialState(runtime: runtime)
        state.workspace.projects = PreviewFixtures.projectsState
        state.agent.agents = PreviewFixtures.agentState
        state.shell.layout.selectedMainView = mainView

        if let vscodeSession {
            let workspaceID = vscodeSession.workspaceSelectionID ?? state.workspace.projects.selection.stableID
            state.editor.sessionsByWorkspaceID[workspaceID] = vscodeSession
            state.editor.selectedWorkspaceID = workspaceID
        }

        state.workbench.initializeDefaultTabs(
            layout: state.shell.layout,
            projects: state.workspace.projects,
            agents: state.agent.agents
        )

        let store = Store(
            initialState: state,
            reducer: { AppFeature() },
            withDependencies: { dependencies in
                dependencies.configClient = ConfigClient.liveValue
                dependencies.gitClient = GitClient.liveValue
                dependencies.importPanelClient = ImportPanelClient.liveValue
                dependencies.fileSystemClient = FileSystemClient.liveValue
                dependencies.layoutPersistenceClient = LayoutPersistenceClient(
                    persistUIState: { _, _ in }
                )
                dependencies.openCodeConfigClient = OpenCodeConfigClient.liveValue
                dependencies.terminalRegistryClient = TerminalRegistryClient(
                    agentController: { _ in nil },
                    workspaceController: { _, _, _ in
                        fatalError("Preview terminal controller creation unsupported.")
                    },
                    workspaceControllerIfLoaded: { _ in nil },
                    releaseAgentController: { _ in },
                    setAgentAttached: { _, _ in },
                    setWorkspaceAttached: { _, _ in },
                    shutdownAll: { _, _ in
                        TerminalRegistryShutdownSummary(
                            sessionCount: 0,
                            forcedKillCount: 0,
                            timedOutCount: 0
                        )
                    }
                )
                dependencies.agentRuntimeClient = AgentRuntimeClient(
                    buildLaunchPlan: { name, command, _, _ in
                        AgentRuntimeLaunchPlan(
                            startupTitle: name,
                            runtimeCommand: command,
                            expectsRichStatus: false
                        )
                    },
                    start: { _, _, _, _ in AsyncStream { $0.finish() } }
                )
                dependencies.vscodeRuntimeClient = VSCodeRuntimeClient(
                    start: { _, _, _ in
                        AsyncThrowingStream { continuation in
                            continuation.finish()
                        }
                    },
                    browserEvents: {
                        AsyncStream { _ in }
                    },
                    shutdown: { _, _ in
                        VSCodeServerShutdownSummary(didForceKill: false, didTimeout: false)
                    },
                    stop: { },
                    prepareWebRuntime: { _ in },
                    webRuntimeIfPrepared: { _ in nil },
                    loadWorkspaceInBrowser: { _, _, _ in .runtimeUnavailable },
                    invalidateBrowserAddresses: { },
                    syncBrowserRuntimeCache: { _ in },
                    removeBrowserRuntime: { _ in }
                )
                dependencies.appControlClient = AppControlClient(
                    activateMainWindowForExternalOpen: { },
                    requestApplicationQuit: { }
                )
                dependencies.appLifecycleBridgeClient = AppLifecycleBridgeClient(
                    completeTerminationRequest: { _, _ in }
                )
                dependencies.windowClient = .noop
            }
        )
        let composition = AppComposition.preview(
            runtime: runtime,
            editorRuntime: EditorRuntime(),
            store: store
        )
        return ContentView(store: store, composition: composition)
    }
}

import CoreGraphics
import Foundation

enum AppBootstrap {
    @MainActor
    static func makeInitialState(runtime: AppRuntime) -> AppFeature.State {
        let loadResult = runtime.configStore.loadResultEnsuringManagedFiles()
        let persistedUIState = runtime.uiStateStore.load()
        let configNotification = ConfigClient.liveValue.diagnosticsMessage(
            loadResult.diagnostics,
            runtime.configStore.configURL
        )
        var layout = PreviewFixtures.layoutState
        if let persistedThemeMode = persistedUIState.layout.themeMode,
           let resolvedThemeMode = ThemeMode(rawValue: persistedThemeMode) {
            layout.themeMode = resolvedThemeMode
        }
        if let previewWidth = persistedUIState.layout.preferredPreviewWidth {
            layout.preferredPreviewWidth = CGFloat(previewWidth)
        }
        if let leftWidth = persistedUIState.layout.preferredLeftSidebarWidth {
            layout.preferredLeftSidebarWidth = CGFloat(leftWidth)
        }
        if let rightWidth = persistedUIState.layout.preferredRightSidebarWidth {
            layout.preferredRightSidebarWidth = CGFloat(rightWidth)
        }

        let projects = ProjectsState.fromImportedProjects(
            [],
            collapsedProjectPaths: Set(persistedUIState.workspace.collapsedProjectPaths),
            collapsedSectionIDs: Set(persistedUIState.workspace.collapsedSectionIDs)
        )
        let initialWorkspaceID = projects.selection.stableID

        return AppFeature.State(
            shell: ShellFeature.State(
                layout: layout,
                resolvedShortcuts: loadResult.config.resolvedShortcuts,
                terminalConfig: loadResult.config.terminal,
                themeSet: loadResult.config.theme,
                configNotification: configNotification,
                dismissedConfigNotificationSignature: nil,
                commandBarShouldRestorePreviousFocus: true,
                surfaceFocusRequest: nil,
                windowChrome: WindowChromeState()
            ),
            workbench: WorkbenchFeature.State(
                surfaceTabs: SurfaceTabState(),
                surfaceMountState: SurfaceMountState(),
                nextSurfaceFocusRequestID: 0
            ),
            workspace: WorkspaceFeature.State(projects: projects),
            agent: AgentFeature.State(agents: PreviewFixtures.agentState),
            editor: EditorFeature.State(
                sessionsByWorkspaceID: [:],
                selectedWorkspaceID: initialWorkspaceID,
                vscodeMountedWorkspaceIDs: []
            ),
            commandPalette: CommandPaletteFeature.State(commandBar: CommandBarState()),
            lifecycle: LifecycleFeature.State()
        )
    }
}

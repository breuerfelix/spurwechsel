import AppKit
import Combine
import SwiftUI

struct AppTerminationSummary: Equatable {
    var forcedKillCount: Int
    var timedOutCount: Int
}

@MainActor
final class SpurwechselAppStore: ObservableObject {
    let shellStore: ShellStore
    let workspaceStore: WorkspaceStore
    let agentStore: AgentSessionsStore
    let terminalStore: TerminalStore
    let editorStore: EditorStore
    let commandPaletteStore: CommandPaletteStore
    let workbenchStore: WorkbenchStore

    var layout: AppLayoutState {
        get { shellStore.layout }
        set { shellStore.layout = newValue }
    }

    var projects: ProjectsState {
        get { workspaceStore.projects }
        set { workspaceStore.projects = newValue }
    }

    var agents: AgentState {
        get { agentStore.agents }
        set { agentStore.agents = newValue }
    }

    var vscodeServer: VSCodeServerState {
        get {
            let workspaceID = editorStore.selectedWorkspaceID ?? workspaceStore.projects.selection.stableID
            return editorStore.sessionsByWorkspaceID[workspaceID] ?? VSCodeServerState(
                workspaceSelectionID: workspaceID,
                workspaceName: nil,
                workspacePath: nil,
                serverAddress: nil,
                workspaceAddress: nil,
                status: .idle,
                statusMessage: "Select VSCode view to start code-server.",
                errorMessage: nil,
                lastOutputLine: nil
            )
        }
        set {
            let workspaceID = newValue.workspaceSelectionID ?? editorStore.selectedWorkspaceID ?? workspaceStore.projects.selection.stableID
            editorStore.selectedWorkspaceID = workspaceID
            editorStore.sessionsByWorkspaceID[workspaceID] = newValue
        }
    }

    private(set) var appShutdown: AppShutdownState {
        get { shellStore.appShutdown }
        set { shellStore.updateShutdown { $0 = newValue } }
    }

    private(set) var configNotification: ConfigNotificationState? {
        get { shellStore.configNotification }
        set { shellStore.setConfigNotification(newValue) }
    }

    var commandBar: CommandBarState {
        get { commandPaletteStore.commandBar }
        set { commandPaletteStore.commandBar = newValue }
    }

    var surfaceTabs: SurfaceTabState {
        get { workbenchStore.surfaceTabs }
        set { workbenchStore.surfaceTabs = newValue }
    }

    private(set) var surfaceMountState: SurfaceMountState {
        get { workbenchStore.surfaceMountState }
        set { workbenchStore.mountSurface(newValue.mainSurfaceID, in: .main)
            workbenchStore.mountSurface(newValue.previewSurfaceID, in: .preview)
        }
    }

    var appIsActive: Bool {
        shellStore.appIsActive
    }

    var windowIsKey: Bool {
        shellStore.windowIsKey
    }

    private(set) var commandBarShouldRestorePreviousFocus: Bool {
        get { shellStore.commandBarShouldRestorePreviousFocus }
        set { shellStore.setCommandBarFocusRestore(newValue) }
    }

    private(set) var surfaceFocusRequest: SurfaceFocusRequest? {
        get { shellStore.surfaceFocusRequest }
        set { shellStore.setSurfaceFocusRequest(newValue) }
    }

    let previewModels: [PreviewContentModel]
    var projectConfig: SpurwechselConfig
    var fileConfig: UserConfigFile

    let dependencies: AppDependencies
    let configStore: ProjectConfigStore
    let importURLsProvider: () -> [URL]?
    let applicationQuitHandler: @MainActor () -> Void
    let gitService: GitRepositoryServicing
    let terminalRegistry: TerminalSessionRegistry
    let vscodeServerRuntime: VSCodeServerRuntime
    private var childStoreBindings = Set<AnyCancellable>()
    lazy var coordinator = AppCoordinator(store: self)
    lazy var commandPaletteViewStore = CommandPaletteViewStore(appStore: self)
    lazy var agentSurfaceStore = AgentSurfaceStore(appStore: self)
    lazy var terminalSurfaceStore = TerminalSurfaceStore(appStore: self)
    lazy var editorSurfaceStore = EditorSurfaceStore(appStore: self)

    init(
        layout: AppLayoutState? = nil,
        projects: ProjectsState? = nil,
        agents: AgentState? = nil,
        vscodeServer: VSCodeServerState? = nil,
        previewModels: [PreviewContentModel]? = nil,
        configStore: ProjectConfigStore? = nil,
        gitService: GitRepositoryServicing? = nil,
        importURLsProvider: (() -> [URL]?)? = nil,
        dependencies: AppDependencies? = nil,
        applicationQuitHandler: @escaping @MainActor () -> Void = { NSApp.terminate(nil) }
    ) {
        let resolvedDependencies = dependencies ?? AppDependencies.live(
            configStore: configStore,
            gitService: gitService,
            importURLsProvider: importURLsProvider
        )
        self.dependencies = resolvedDependencies
        self.configStore = resolvedDependencies.configStore
        self.gitService = resolvedDependencies.gitService
        self.importURLsProvider = resolvedDependencies.importURLsProvider
        self.applicationQuitHandler = applicationQuitHandler
        self.terminalRegistry = resolvedDependencies.terminalRegistry
        self.vscodeServerRuntime = resolvedDependencies.vscodeServerRuntime

        let loadResult = self.configStore.loadResultEnsuringManagedFiles()
        let loadedProjects = projects ?? ProjectsState.fromImportedProjects([])
        self.shellStore = ShellStore(
            layout: layout ?? PreviewFixtures.layoutState,
            configNotification: Self.makeConfigNotification(
                diagnostics: loadResult.diagnostics,
                configURL: self.configStore.configURL
            ),
            themeSet: loadResult.config.theme
        )
        self.workspaceStore = WorkspaceStore(projects: loadedProjects)
        self.agentStore = AgentSessionsStore(agents: agents ?? PreviewFixtures.agentState)
        self.terminalStore = TerminalStore()
        let initialWorkspaceID = loadedProjects.selection.stableID
        var initialEditorSessions: [String: EditorSessionState] = [:]
        if let vscodeServer {
            initialEditorSessions[initialWorkspaceID] = vscodeServer
        }
        self.editorStore = EditorStore(
            sessionsByWorkspaceID: initialEditorSessions,
            selectedWorkspaceID: initialWorkspaceID
        )
        self.commandPaletteStore = CommandPaletteStore(commandBar: CommandBarState())
        self.workbenchStore = WorkbenchStore(
            surfaceTabs: SurfaceTabState(),
            surfaceMountState: SurfaceMountState()
        )
        self.previewModels = previewModels ?? PreviewFixtures.previewModels
        self.projectConfig = loadResult.config
        self.fileConfig = loadResult.fileConfig
        bindChildStores()

        vscodeServerRuntime.onEvent = { [weak self] event in
            self?.coordinator.handleVSCodeServerEvent(event)
        }

        if projects == nil {
            coordinator.refreshProjectsFromConfig()
        }
        if layout?.selectedMainView == .vscode {
            coordinator.ensureVSCodeServerForSelectedWorkspace(forceRestart: false)
        }
        coordinator.initializeSurfaceTabs()
        coordinator.syncMountedSurfaces()
        coordinator.syncTerminalSurfaceActivation()
        coordinator.requestSurfaceFocus(coordinator.preferredSurfaceSlotForCurrentMainView())
    }

    private func bindChildStores() {
        shellStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &childStoreBindings)
        workspaceStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &childStoreBindings)
        agentStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &childStoreBindings)
        terminalStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &childStoreBindings)
        editorStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &childStoreBindings)
        commandPaletteStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &childStoreBindings)
        workbenchStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &childStoreBindings)
    }

    private static func makeConfigNotification(
        diagnostics: [ConfigDiagnostic],
        configURL: URL
    ) -> ConfigNotificationState? {
        guard !diagnostics.isEmpty else {
            return nil
        }

        let issueCount = diagnostics.count
        let firstIssue = diagnostics[0].message
        let detailSuffix = issueCount > 1 ? " \(issueCount - 1) more issue(s)." : ""
        return ConfigNotificationState(
            title: "Config invalid",
            message: "Using defaults for invalid settings in \(abbreviatedPath(configURL.path)).",
            detailMessage: firstIssue + detailSuffix
        )
    }

    private static func abbreviatedPath(_ path: String) -> String {
        let homeDirectory = NSHomeDirectory()
        guard path.hasPrefix(homeDirectory) else {
            return path
        }
        return path.replacingOccurrences(of: homeDirectory, with: "~")
    }

}

import AppKit
import Foundation
import os

@MainActor
enum AppIntent: Equatable {
    case toggleCommandBar
    case openCommandBar(projectContextID: UUID?, workspaceContext: WorkspaceSelection?)
    case closeCommandBar(restorePreviousFocus: Bool)
    case executeCommand(CommandID, projectContextID: UUID?, workspaceContext: WorkspaceSelection?)
    case toggleLeftSidebar
    case toggleRightSidebar
    case togglePreview
    case toggleTheme
    case selectMainView(MainViewKind)
    case selectPreviewView(PreviewViewKind)
    case selectWorkspace(WorkspaceSelection)
    case selectSurface(SurfaceTabID)
    case addWorktree(UUID)
    case toggleProjectCollapse(UUID)
    case addAgent(WorkspaceSelection)
    case selectAgentSession(UUID)
    case deleteAgent(UUID)
}

@MainActor
final class AppCoordinator {
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "dev.breuer.spurwechsel",
        category: "SpurwechselAppCoordinator"
    )
    static let shutdownGraceTimeout: TimeInterval = 2.0
    static let shutdownForceKillTimeout: TimeInterval = 1.5
    static let shortcutModifierMask: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
    static let maxWarmVSCodeRuntimes = 6

    unowned let store: SpurwechselAppStore

    var inFlightAppShutdownTask: Task<AppTerminationSummary, Never>?
    var vscodeWebRuntimesByWorkspaceID: [String: EmbeddedWebViewRuntime] = [:]
    var isSelectingSurfaceTab = false
    var nextSurfaceFocusRequestID = 0
    var projectIDsByRecordPath: [String: UUID] = [:]
    var worktreeIDsByPath: [String: UUID] = [:]

    init(store: SpurwechselAppStore) {
        self.store = store
    }

    func handle(_ intent: AppIntent) {
        switch intent {
        case .toggleCommandBar:
            toggleCommandBar()
        case let .openCommandBar(projectContextID, workspaceContext):
            openCommandBar(
                projectContextID: projectContextID,
                workspaceContext: workspaceContext
            )
        case let .closeCommandBar(restorePreviousFocus):
            closeCommandBar(restorePreviousFocus: restorePreviousFocus)
        case let .executeCommand(command, projectContextID, workspaceContext):
            executeCommand(
                command,
                projectContextID: projectContextID,
                workspaceContext: workspaceContext
            )
        case .toggleLeftSidebar:
            toggleLeftSidebar()
        case .toggleRightSidebar:
            toggleRightSidebar()
        case .togglePreview:
            togglePreview()
        case .toggleTheme:
            toggleTheme()
        case let .selectMainView(view):
            selectMainView(view)
        case let .selectPreviewView(view):
            selectPreviewView(view)
        case let .selectWorkspace(selection):
            selectWorkspace(selection)
        case let .selectSurface(surfaceID):
            selectSurfaceTab(surfaceID)
        case let .addWorktree(projectID):
            addWorktree(to: projectID)
        case let .toggleProjectCollapse(projectID):
            toggleProjectCollapse(projectID)
        case let .addAgent(selection):
            addAgent(to: selection)
        case let .selectAgentSession(sessionID):
            selectSession(sessionID)
        case let .deleteAgent(sessionID):
            deleteAgent(sessionID: sessionID)
        }
    }
}

@MainActor
extension AppCoordinator {
    var shellStore: ShellStore { store.shellStore }
    var workspaceStore: WorkspaceStore { store.workspaceStore }
    var agentStore: AgentSessionsStore { store.agentStore }
    var terminalStore: TerminalStore { store.terminalStore }
    var editorStore: EditorStore { store.editorStore }
    var commandPaletteStore: CommandPaletteStore { store.commandPaletteStore }
    var workbenchStore: WorkbenchStore { store.workbenchStore }

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
        get { store.vscodeServer }
        set { store.vscodeServer = newValue }
    }

    var editorSessionsByWorkspaceID: [String: EditorSessionState] {
        get { editorStore.sessionsByWorkspaceID }
        set { editorStore.sessionsByWorkspaceID = newValue }
    }

    var selectedEditorWorkspaceID: String? {
        get { editorStore.selectedWorkspaceID }
        set { editorStore.selectedWorkspaceID = newValue }
    }

    var commandBar: CommandBarState {
        get { commandPaletteStore.commandBar }
        set { commandPaletteStore.commandBar = newValue }
    }

    var surfaceTabs: SurfaceTabState {
        get { workbenchStore.surfaceTabs }
        set { workbenchStore.surfaceTabs = newValue }
    }

    var surfaceMountState: SurfaceMountState {
        get { workbenchStore.surfaceMountState }
        set {
            workbenchStore.mountSurface(newValue.mainSurfaceID, in: .main)
            workbenchStore.mountSurface(newValue.previewSurfaceID, in: .preview)
        }
    }

    var appIsActive: Bool { shellStore.appIsActive }
    var windowIsKey: Bool { shellStore.windowIsKey }
    var previewModels: [PreviewContentModel] { store.previewModels }
    var projectConfig: SpurwechselConfig {
        get { store.projectConfig }
        set {
            store.projectConfig = newValue
            shellStore.setThemeSet(newValue.theme)
        }
    }
    var fileConfig: UserConfigFile {
        get { store.fileConfig }
        set { store.fileConfig = newValue }
    }
    var configStore: ProjectConfigStore { store.configStore }
    var uiStateStore: UIStateStore { store.uiStateStore }
    var importURLsProvider: () -> [URL]? { store.importURLsProvider }
    var gitService: GitRepositoryServicing { store.gitService }
    var terminalRegistry: TerminalSessionRegistry { store.terminalRegistry }
    var vscodeMountedWorkspaceIDs: [String] {
        get { editorStore.vscodeMountedWorkspaceIDs }
        set { editorStore.setMountedWorkspaceIDs(newValue) }
    }
    var vscodeServerRuntime: VSCodeServerRuntime { store.vscodeServerRuntime }
}

@MainActor
extension AppCoordinator {
    static func fuzzyScore(query: String, candidate: String) -> Int? {
        let filteredQuery = query
            .lowercased()
            .filter { !$0.isWhitespace }
        let loweredCandidate = candidate.lowercased()
        var searchIndex = loweredCandidate.startIndex
        var totalDistance = 0

        for queryCharacter in filteredQuery {
            guard let matchIndex = loweredCandidate[searchIndex...].firstIndex(of: queryCharacter) else {
                return nil
            }

            totalDistance += loweredCandidate.distance(from: searchIndex, to: matchIndex)
            searchIndex = loweredCandidate.index(after: matchIndex)
        }

        return totalDistance
    }

    static func normalizedShortcutKey(from event: NSEvent) -> String? {
        guard let rawKey = event.charactersIgnoringModifiers else {
            return nil
        }

        let normalizedKey = ResolvedShortcutBinding.normalizeKey(rawKey)
        guard normalizedKey.count == 1 else {
            return nil
        }

        return normalizedKey
    }

    static func shortcutModifiers(from event: NSEvent) -> Set<ShortcutModifier> {
        let normalizedFlags = event.modifierFlags.intersection(shortcutModifierMask)
        var modifiers = Set<ShortcutModifier>()

        if normalizedFlags.contains(.command) {
            modifiers.insert(.command)
        }
        if normalizedFlags.contains(.shift) {
            modifiers.insert(.shift)
        }
        if normalizedFlags.contains(.option) {
            modifiers.insert(.option)
        }
        if normalizedFlags.contains(.control) {
            modifiers.insert(.control)
        }

        return modifiers
    }

    func normalizePath(_ path: String) -> String {
        configStore.normalizeDirectoryPath(URL(fileURLWithPath: path))
    }
}

import AppKit
import Combine
import Foundation

@MainActor
struct AppDependencies {
    let configStore: ProjectConfigStore
    let gitService: GitRepositoryServicing
    let importURLsProvider: () -> [URL]?
    let terminalRegistry: TerminalSessionRegistry
    let vscodeServerRuntime: VSCodeServerRuntime

    static func live(
        configStore: ProjectConfigStore? = nil,
        gitService: GitRepositoryServicing? = nil,
        importURLsProvider: (() -> [URL]?)? = nil
    ) -> AppDependencies {
        AppDependencies(
            configStore: configStore ?? ProjectConfigStore(),
            gitService: gitService ?? GitRepositoryService(),
            importURLsProvider: importURLsProvider ?? defaultImportURLsProvider(),
            terminalRegistry: TerminalSessionRegistry(),
            vscodeServerRuntime: VSCodeServerRuntime()
        )
    }

    private static func defaultImportURLsProvider(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> () -> [URL]? {
        {
            if let rawTestPaths = environment["SPURWECHSEL_TEST_IMPORT_PATHS"] {
                let trimmed = rawTestPaths.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    return []
                }

                return trimmed
                    .split(separator: "|")
                    .map { URL(fileURLWithPath: String($0)) }
            }

            let openPanel = NSOpenPanel()
            openPanel.canChooseFiles = false
            openPanel.canChooseDirectories = true
            openPanel.allowsMultipleSelection = true
            openPanel.canCreateDirectories = false
            openPanel.prompt = "Add Project"
            openPanel.title = "Add New Project"

            return openPanel.runModal() == .OK ? openPanel.urls : nil
        }
    }
}

@MainActor
final class ShellStore: ObservableObject {
    @Published var layout: AppLayoutState
    @Published private(set) var themeSet: ThemeSet
    @Published private(set) var appShutdown = AppShutdownState()
    @Published private(set) var configNotification: ConfigNotificationState?
    @Published private(set) var appIsActive = true
    @Published private(set) var windowIsKey = true
    @Published private(set) var commandBarShouldRestorePreviousFocus = true
    @Published private(set) var surfaceFocusRequest: SurfaceFocusRequest?
    @Published private(set) var windowChrome = WindowChromeState()

    init(
        layout: AppLayoutState,
        configNotification: ConfigNotificationState?,
        themeSet: ThemeSet
    ) {
        self.layout = layout
        self.configNotification = configNotification
        self.themeSet = themeSet
    }

    var theme: SpurTheme { themeSet.spurTheme(for: layout.themeMode) }

    var terminalSurfacesAreForeground: Bool {
        appIsActive && windowIsKey
    }

    func dismissConfigNotification() {
        configNotification = nil
    }

    func setApplicationActive(_ isActive: Bool) {
        guard appIsActive != isActive else {
            return
        }
        appIsActive = isActive
    }

    func setWindowKey(_ isKey: Bool) {
        guard windowIsKey != isKey else {
            return
        }
        windowIsKey = isKey
    }

    func setCommandBarFocusRestore(_ shouldRestore: Bool) {
        commandBarShouldRestorePreviousFocus = shouldRestore
    }

    func beginShutdown() {
        appShutdown.isInProgress = true
        appShutdown.statusMessage = "Shutting everything down…"
        appShutdown.detailMessage = "Closing terminals, agents, and background sessions."
    }

    func setShutdownProgress(status: String, detail: String) {
        appShutdown.statusMessage = status
        appShutdown.detailMessage = detail
    }

    func updateShutdown(_ update: (inout AppShutdownState) -> Void) {
        update(&appShutdown)
    }

    func setConfigNotification(_ notification: ConfigNotificationState?) {
        configNotification = notification
    }

    func setSurfaceFocusRequest(_ request: SurfaceFocusRequest?) {
        surfaceFocusRequest = request
    }

    func setThemeSet(_ themeSet: ThemeSet) {
        self.themeSet = themeSet
    }

    func setWindowChrome(_ windowChrome: WindowChromeState) {
        guard self.windowChrome != windowChrome else {
            return
        }
        self.windowChrome = windowChrome
    }

    func setTopBarFrameInWindow(_ frame: CGRect?) {
        guard windowChrome.topBarFrameInWindow != frame else {
            return
        }
        var nextState = windowChrome
        nextState.topBarFrameInWindow = frame
        windowChrome = nextState
    }
}

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published var projects: ProjectsState

    init(projects: ProjectsState) {
        self.projects = projects
    }
}

@MainActor
final class AgentSessionsStore: ObservableObject {
    @Published var agents: AgentState

    init(agents: AgentState) {
        self.agents = agents
    }
}

@MainActor
final class EditorStore: ObservableObject {
    @Published var sessionsByWorkspaceID: [String: EditorSessionState]
    @Published var selectedWorkspaceID: String?
    @Published private(set) var vscodeMountedWorkspaceIDs: [String]

    init(
        sessionsByWorkspaceID: [String: EditorSessionState] = [:],
        selectedWorkspaceID: String? = nil,
        vscodeMountedWorkspaceIDs: [String] = []
    ) {
        self.sessionsByWorkspaceID = sessionsByWorkspaceID
        self.selectedWorkspaceID = selectedWorkspaceID
        self.vscodeMountedWorkspaceIDs = vscodeMountedWorkspaceIDs
    }

    func setMountedWorkspaceIDs(_ ids: [String]) {
        vscodeMountedWorkspaceIDs = ids
    }
}

@MainActor
final class TerminalStore: ObservableObject {
    @Published var sessionsByWorkspaceID: [String: TerminalSessionState]

    init(sessionsByWorkspaceID: [String: TerminalSessionState] = [:]) {
        self.sessionsByWorkspaceID = sessionsByWorkspaceID
    }
}

@MainActor
final class CommandPaletteStore: ObservableObject {
    @Published var commandBar: CommandBarState

    init(commandBar: CommandBarState) {
        self.commandBar = commandBar
    }
}

@MainActor
final class WorkbenchStore: ObservableObject {
    @Published var surfaceTabs: SurfaceTabState
    @Published private(set) var surfaceMountState: SurfaceMountState

    init(
        surfaceTabs: SurfaceTabState,
        surfaceMountState: SurfaceMountState
    ) {
        self.surfaceTabs = surfaceTabs
        self.surfaceMountState = surfaceMountState
    }

    func mountSurface(_ surfaceID: SurfaceTabID?, in slot: SurfaceSlot) {
        surfaceMountState.mount(surfaceID, in: slot)
    }
}

import CoreGraphics
import Foundation

enum SurfaceKind: String, CaseIterable, Hashable {
    case agent
    case terminal
    case vscode

    var title: String {
        switch self {
        case .vscode:
            return "VSCode"
        default:
            return rawValue.capitalized
        }
    }

    var symbolName: String {
        switch self {
        case .agent:
            return "sparkles.rectangle.stack"
        case .terminal:
            return "terminal"
        case .vscode:
            return "chevron.left.forwardslash.chevron.right"
        }
    }
}

typealias MainViewKind = SurfaceKind
typealias PreviewViewKind = SurfaceKind

extension SurfaceKind {
    func conflicts(with mainView: MainViewKind) -> Bool {
        self == mainView
    }

    var mainViewKind: MainViewKind {
        self
    }
}

enum SurfaceDescriptor: Hashable {
    case agentSession(UUID)
    case agentWorkspace(String)
    case workspaceTerminal(String)
    case vscodeWorkspace(String)

    var mainView: MainViewKind {
        switch self {
        case .agentSession, .agentWorkspace:
            return .agent
        case .workspaceTerminal:
            return .terminal
        case .vscodeWorkspace:
            return .vscode
        }
    }
}

typealias SurfaceTabID = SurfaceDescriptor

struct SurfaceTab: Identifiable, Equatable {
    let id: SurfaceTabID
    var title: String
    var workspaceSelection: WorkspaceSelection
    var sessionID: UUID?

    var mainView: MainViewKind {
        id.mainView
    }
}

struct SurfaceTabState: Equatable {
    var tabs: [SurfaceTab] = []
    var selectedTabID: SurfaceTabID?

    var selectedTab: SurfaceTab? {
        guard let selectedTabID else { return nil }
        return tabs.first(where: { $0.id == selectedTabID })
    }
}

enum SurfacePlacement: Hashable {
    case main
    case preview
}

typealias SurfaceSlot = SurfacePlacement

struct SurfaceFocusRequest: Equatable {
    let id: Int
    let slot: SurfaceSlot
}

struct SurfaceMountState: Equatable {
    private(set) var mountedBySlot: [SurfaceSlot: SurfaceTabID] = [:]

    var mainSurfaceID: SurfaceTabID? {
        mountedBySlot[.main]
    }

    var previewSurfaceID: SurfaceTabID? {
        mountedBySlot[.preview]
    }

    mutating func mount(_ surfaceID: SurfaceTabID?, in slot: SurfaceSlot) {
        if let surfaceID {
            for occupiedSlot in mountedBySlot.keys where occupiedSlot != slot && mountedBySlot[occupiedSlot] == surfaceID {
                mountedBySlot.removeValue(forKey: occupiedSlot)
            }
            mountedBySlot[slot] = surfaceID
        } else {
            mountedBySlot.removeValue(forKey: slot)
        }
    }
}

enum ThemeMode: String, CaseIterable, Hashable {
    case dark
    case light

    var title: String {
        rawValue.capitalized
    }

    var symbolName: String {
        switch self {
        case .dark:
            return "moon.stars.fill"
        case .light:
            return "sun.max.fill"
        }
    }
}

enum CommandID: String, CaseIterable, Hashable, Codable {
    case toggleCommandBar = "toggle-command-bar"
    case addProject = "add-new-project"
    case removeProject = "remove-project"
    case addWorktree = "add-worktree"
    case deleteWorktree = "delete-worktree"
    case selectProject = "select-project"
    case selectNextProject = "select-next-project"
    case selectPreviousProject = "select-previous-project"
    case createAgent = "create-agent"
    case createDefaultAgent = "create-default-agent"
    case deleteAgent = "delete-agent"
    case selectPreviousAgent = "select-previous-agent"
    case selectNextAgent = "select-next-agent"
    case openTerminalView = "open-terminal-view"
    case openVSCodeView = "open-vscode-view"
    case openAgentView = "open-agent-view"
    case togglePreviewPane = "toggle-preview-pane"
    case toggleRightSidebar = "toggle-right-sidebar"
    case toggleLeftSidebar = "toggle-left-sidebar"
    case quit = "quit"

    var title: String {
        switch self {
        case .toggleCommandBar:
            return "Toggle Command Bar"
        case .addProject:
            return "Add New Project"
        case .removeProject:
            return "Remove Project"
        case .addWorktree:
            return "Add Worktree"
        case .deleteWorktree:
            return "Delete Worktree"
        case .selectProject:
            return "Select Project"
        case .selectNextProject:
            return "Select Next Project"
        case .selectPreviousProject:
            return "Select Previous Project"
        case .createAgent:
            return "Create Agent"
        case .createDefaultAgent:
            return "Create Default Agent"
        case .deleteAgent:
            return "Delete Agent"
        case .selectPreviousAgent:
            return "Select Previous Agent"
        case .selectNextAgent:
            return "Select Next Agent"
        case .openTerminalView:
            return "Open Terminal View"
        case .openVSCodeView:
            return "Open VSCode View"
        case .openAgentView:
            return "Open Agent View"
        case .togglePreviewPane:
            return "Toggle Preview Pane"
        case .toggleRightSidebar:
            return "Toggle Right Sidebar"
        case .toggleLeftSidebar:
            return "Toggle Left Sidebar"
        case .quit:
            return "Quit"
        }
    }

    var symbolName: String {
        switch self {
        case .toggleCommandBar:
            return "magnifyingglass"
        case .addProject:
            return "folder.badge.plus"
        case .removeProject:
            return "folder.badge.minus"
        case .addWorktree, .deleteWorktree:
            return "point.3.filled.connected.trianglepath.dotted"
        case .selectProject, .selectNextProject, .selectPreviousProject:
            return "folder"
        case .createAgent, .createDefaultAgent, .deleteAgent, .selectPreviousAgent, .selectNextAgent, .openAgentView:
            return "sparkles.rectangle.stack"
        case .openTerminalView:
            return "terminal"
        case .openVSCodeView:
            return "chevron.left.forwardslash.chevron.right"
        case .togglePreviewPane:
            return "rectangle.split.2x1"
        case .toggleRightSidebar:
            return "sidebar.right"
        case .toggleLeftSidebar:
            return "sidebar.left"
        case .quit:
            return "xmark.circle"
        }
    }

    var keywords: [String] {
        switch self {
        case .toggleCommandBar:
            return ["command", "palette", "bar", "search", "toggle"]
        case .addProject:
            return ["new", "project", "folder", "import", "workspace"]
        case .removeProject:
            return ["remove", "delete", "project", "workspace", "forget"]
        case .addWorktree:
            return ["worktree", "branch", "create", "new", "project"]
        case .deleteWorktree:
            return ["worktree", "remove", "delete", "branch", "cleanup"]
        case .selectProject:
            return ["project", "worktree", "switch", "select", "find"]
        case .selectNextProject:
            return ["project", "worktree", "next", "switch", "cycle"]
        case .selectPreviousProject:
            return ["project", "worktree", "previous", "switch", "cycle"]
        case .createAgent:
            return ["agent", "terminal", "run", "launch"]
        case .createDefaultAgent:
            return ["agent", "default", "run", "launch"]
        case .deleteAgent:
            return ["agent", "delete", "remove", "kill", "close"]
        case .selectPreviousAgent:
            return ["agent", "previous", "select", "switch", "cycle"]
        case .selectNextAgent:
            return ["agent", "next", "select", "switch", "cycle"]
        case .openTerminalView:
            return ["terminal", "view", "shell", "console"]
        case .openVSCodeView:
            return ["vscode", "view", "code", "editor", "ide"]
        case .openAgentView:
            return ["agent", "view", "ai", "assistant"]
        case .togglePreviewPane:
            return ["preview", "pane", "toggle", "panel"]
        case .toggleRightSidebar:
            return ["right", "sidebar", "toggle", "panel"]
        case .toggleLeftSidebar:
            return ["left", "sidebar", "toggle", "panel"]
        case .quit:
            return ["quit", "exit", "close", "application", "app"]
        }
    }

    var accessibilityID: String {
        rawValue
    }
}

struct CommandBarNotice: Equatable {
    var text: String
    var isError: Bool
}

enum CommandBarPickerPayload: Equatable {
    case deleteWorktree(projectID: UUID, worktreeID: UUID)
    case selectWorkspace(WorkspaceSelection)
    case createAgent(
        workspaceSelection: WorkspaceSelection,
        agentName: String,
        command: String
    )
}

struct CommandBarPickerItem: Identifiable, Equatable {
    var id: String
    var title: String
    var subtitle: String
    var symbolName: String
    var payload: CommandBarPickerPayload
}

enum CommandBarTextAction: Equatable {
    case addWorktree(projectID: UUID)
}

struct CommandBarTextPrompt: Equatable {
    var title: String
    var placeholder: String
    var submitTitle: String
    var action: CommandBarTextAction
}

enum CommandBarConfirmationAction: Equatable {
    case deleteWorktree(projectID: UUID, worktreeID: UUID)
    case deleteAgent(sessionID: UUID)
    case removeProject(projectID: UUID)
}

struct CommandBarConfirmationPrompt: Equatable {
    var title: String
    var message: String
    var confirmTitle: String
    var action: CommandBarConfirmationAction
}

enum CommandBarMode: Equatable {
    case commandList
    case textInput(CommandBarTextPrompt)
    case picker(title: String, items: [CommandBarPickerItem], emptyMessage: String)
    case confirmation(CommandBarConfirmationPrompt)
}

struct CommandBarState: Equatable {
    var isPresented = false
    var mode: CommandBarMode = .commandList
    var query = ""
    var textInput = ""
    var highlightedIndex = 0
    var projectContextID: UUID?
    var workspaceContext: WorkspaceSelection?
    var notice: CommandBarNotice?

    mutating func resetQuery() {
        query = ""
        highlightedIndex = 0
    }

    mutating func presentCommandList(
        projectContextID: UUID? = nil,
        workspaceContext: WorkspaceSelection? = nil
    ) {
        isPresented = true
        mode = .commandList
        self.projectContextID = projectContextID
        self.workspaceContext = workspaceContext
        textInput = ""
        notice = nil
        resetQuery()
    }

    mutating func close() {
        isPresented = false
        mode = .commandList
        projectContextID = nil
        workspaceContext = nil
        textInput = ""
        notice = nil
        resetQuery()
    }
}

enum VSCodeServerStatus: Hashable {
    case idle
    case missingWorkspace
    case starting
    case running
    case authRequired
    case stopping
    case stopped
    case cliMissing
    case portInUse
    case startupFailed
    case urlNotFound
}

struct VSCodeServerState: Equatable {
    var workspaceSelectionID: String?
    var workspaceName: String?
    var workspacePath: String?
    var serverAddress: String?
    var workspaceAddress: String?
    var status: VSCodeServerStatus = .idle
    var statusMessage = "Select VSCode view to start code-server."
    var errorMessage: String?
    var lastOutputLine: String?
}

typealias EditorSessionState = VSCodeServerState

struct TerminalSessionState: Equatable {
    var workspaceSelectionID: String
    var isAttached = false
}

struct AppShutdownState: Equatable {
    var isInProgress = false
    var statusMessage = "Shutting everything down…"
    var detailMessage = "Closing terminals, agents, and background sessions."
}

struct ConfigNotificationState: Equatable {
    var title: String
    var message: String
    var detailMessage: String?
}

struct MainViewPreviewConfiguration: Equatable {
    var isEnabled: Bool
    var selectedView: PreviewViewKind
}

struct AppLayoutState: Equatable {
    var selectedMainView: MainViewKind = .agent
    var previewConfigurations: [MainViewKind: MainViewPreviewConfiguration] = [:]
    var preferredFocusedSlotByMainView: [MainViewKind: SurfaceSlot] = [:]
    var preferredPreviewWidth: CGFloat?
    var preferredLeftSidebarWidth: CGFloat?
    var preferredRightSidebarWidth: CGFloat?
    var showsLeftSidebar = true
    var showsRightSidebar = true
    var themeMode: ThemeMode = .dark

    var effectiveShowsLeftSidebar: Bool {
        switch selectedMainView {
        case .terminal, .vscode:
            return false
        case .agent:
            return showsLeftSidebar
        }
    }

    var effectivePreviewConfiguration: MainViewPreviewConfiguration? {
        guard let config = previewConfigurations[selectedMainView] else {
            return nil
        }
        guard !config.selectedView.conflicts(with: selectedMainView) else {
            return nil
        }
        return config
    }

    var previewEnabled: Bool {
        effectivePreviewConfiguration?.isEnabled ?? false
    }

    var selectedPreviewView: PreviewViewKind? {
        effectivePreviewConfiguration?.selectedView
    }

    mutating func toggleLeftSidebar() {
        showsLeftSidebar.toggle()
    }

    mutating func toggleRightSidebar() {
        showsRightSidebar.toggle()
    }

    mutating func selectMainView(_ view: MainViewKind) {
        selectedMainView = view
    }

    mutating func rememberFocusedSlot(_ slot: SurfaceSlot) {
        preferredFocusedSlotByMainView[selectedMainView] = slot
    }

    func preferredFocusedSlot(for mainView: MainViewKind) -> SurfaceSlot {
        preferredFocusedSlotByMainView[mainView] ?? .main
    }

    mutating func togglePreview() {
        let fallbackPreviewView = PreviewViewKind.allCases.first(where: { !$0.conflicts(with: selectedMainView) }) ?? .terminal
        let current = previewConfigurations[selectedMainView] ?? MainViewPreviewConfiguration(
            isEnabled: false,
            selectedView: fallbackPreviewView
        )
        var updated = current
        updated.isEnabled.toggle()
        if updated.selectedView.conflicts(with: selectedMainView) {
            updated.selectedView = fallbackPreviewView
        }
        previewConfigurations[selectedMainView] = updated
    }

    mutating func selectPreviewView(_ view: PreviewViewKind) {
        guard !view.conflicts(with: selectedMainView) else { return }
        var updated = previewConfigurations[selectedMainView] ?? MainViewPreviewConfiguration(isEnabled: false, selectedView: view)
        updated.isEnabled = true
        updated.selectedView = view
        previewConfigurations[selectedMainView] = updated
    }

    mutating func setPreferredPreviewWidth(
        _ width: CGFloat,
        allowedRange: ClosedRange<CGFloat>
    ) {
        preferredPreviewWidth = min(max(width, allowedRange.lowerBound), allowedRange.upperBound)
    }

    mutating func setPreferredLeftSidebarWidth(
        _ width: CGFloat,
        allowedRange: ClosedRange<CGFloat>
    ) {
        preferredLeftSidebarWidth = min(max(width, allowedRange.lowerBound), allowedRange.upperBound)
    }

    mutating func setPreferredRightSidebarWidth(
        _ width: CGFloat,
        allowedRange: ClosedRange<CGFloat>
    ) {
        preferredRightSidebarWidth = min(max(width, allowedRange.lowerBound), allowedRange.upperBound)
    }

    mutating func toggleTheme() {
        themeMode = themeMode == .dark ? .light : .dark
    }
}

struct WindowChromeState: Equatable {
    var topBarFrameInWindow: CGRect?
    var trafficLightsReservedLeadingWidth: CGFloat = 0
    var isFullScreen = false
}

struct WindowChromeLayout: Equatable {
    let closeButtonOrigin: CGPoint
    let miniaturizeButtonOrigin: CGPoint
    let zoomButtonOrigin: CGPoint
    let reservedLeadingWidth: CGFloat
}

enum WindowChromeLayoutResolver {
    static func resolveLayout(
        topBarFrameInWindow: CGRect,
        closeButtonFrame: CGRect,
        miniaturizeButtonFrame: CGRect,
        zoomButtonFrame: CGRect,
        leadingPadding: CGFloat,
        iconGap: CGFloat
    ) -> WindowChromeLayout {
        let miniOffset = miniaturizeButtonFrame.minX - closeButtonFrame.minX
        let zoomOffset = zoomButtonFrame.minX - closeButtonFrame.minX
        let closeOrigin = CGPoint(
            x: topBarFrameInWindow.minX + leadingPadding,
            y: topBarFrameInWindow.midY - (closeButtonFrame.height / 2)
        )
        let miniOrigin = CGPoint(x: closeOrigin.x + miniOffset, y: closeOrigin.y)
        let zoomOrigin = CGPoint(x: closeOrigin.x + zoomOffset, y: closeOrigin.y)
        let clusterMaxX = max(
            closeOrigin.x + closeButtonFrame.width,
            miniOrigin.x + miniaturizeButtonFrame.width,
            zoomOrigin.x + zoomButtonFrame.width
        )
        let reservedLeadingWidth = max(0, clusterMaxX - topBarFrameInWindow.minX + iconGap)

        return WindowChromeLayout(
            closeButtonOrigin: closeOrigin,
            miniaturizeButtonOrigin: miniOrigin,
            zoomButtonOrigin: zoomOrigin,
            reservedLeadingWidth: reservedLeadingWidth
        )
    }
}

struct ProjectsState: Equatable {
    static let fallbackSectionID = ProjectSectionRecord.fallbackID
    static let fallbackSectionTitle = ProjectSectionRecord.fallbackID

    struct SidebarSection: Identifiable, Equatable {
        let id: String
        let title: String
        let projects: [Project]

        var projectCount: Int { projects.count }
    }

    var projects: [Project]
    var configuredSections: [ProjectSectionRecord]
    var collapsedProjectIDs: Set<UUID>
    var collapsedSectionIDs: Set<String>
    var selection: WorkspaceSelection
    var nextProjectCount: Int
    var nextWorktreeCount: Int

    mutating func toggleProjectCollapse(_ projectID: UUID) {
        if collapsedProjectIDs.contains(projectID) {
            collapsedProjectIDs.remove(projectID)
        } else {
            collapsedProjectIDs.insert(projectID)
        }
    }

    mutating func select(_ selection: WorkspaceSelection) {
        self.selection = selection
    }

    mutating func toggleSectionCollapse(_ sectionID: String) {
        if collapsedSectionIDs.contains(sectionID) {
            collapsedSectionIDs.remove(sectionID)
        } else {
            collapsedSectionIDs.insert(sectionID)
        }
    }

    mutating func replaceProjects(
        _ projects: [Project],
        configuredSections: [ProjectSectionRecord]
    ) {
        let previousSelection = selection

        self.projects = projects
        self.configuredSections = configuredSections
        collapsedProjectIDs = collapsedProjectIDs.intersection(Set(projects.map(\.id)))
        collapsedSectionIDs = collapsedSectionIDs.intersection(Set(sidebarSections.map(\.id)))
        nextProjectCount = max(nextProjectCount, projects.count + 1)

        if projects.contains(where: { $0.contains(previousSelection) }) {
            selection = previousSelection
        } else if let firstProject = projects.first {
            selection = .project(firstProject.id)
        } else {
            selection = .project(UUID())
        }
    }

    mutating func addProject() -> Project {
        let project = Project(
            name: "workspace-\(nextProjectCount)",
            branch: "feature/idea-\(nextProjectCount)"
        )
        nextProjectCount += 1
        projects.append(project)
        selection = .project(project.id)
        collapsedProjectIDs.remove(project.id)
        return project
    }

    mutating func addWorktree(to projectID: UUID) -> Worktree? {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            return nil
        }

        let worktree = Worktree(
            name: "explore-\(nextWorktreeCount)",
            branch: "wt/explore-\(nextWorktreeCount)"
        )
        nextWorktreeCount += 1
        projects[projectIndex].worktrees.append(worktree)
        collapsedProjectIDs.remove(projectID)
        selection = .worktree(worktree.id)
        return worktree
    }

    var sidebarSections: [SidebarSection] {
        var groupedProjectsBySectionID: [String: [Project]] = [:]
        for project in projects {
            let sectionIDs = project.sectionIDs.isEmpty
                ? [Self.fallbackSectionID]
                : project.sectionIDs
            for sectionID in sectionIDs {
                groupedProjectsBySectionID[sectionID, default: []].append(project)
            }
        }

        var sections: [SidebarSection] = []
        var consumedSectionIDs = Set<String>()

        for configuredSection in configuredSections {
            guard let sectionProjects = groupedProjectsBySectionID[configuredSection.id],
                  !sectionProjects.isEmpty else {
                continue
            }
            consumedSectionIDs.insert(configuredSection.id)
            sections.append(
                SidebarSection(
                    id: configuredSection.id,
                    title: configuredSection.displayName,
                    projects: sectionProjects
                )
            )
        }

        let remainingSectionIDs = groupedProjectsBySectionID.keys
            .filter { $0 != Self.fallbackSectionID && !consumedSectionIDs.contains($0) }
            .sorted { lhs, rhs in
                lhs.localizedStandardCompare(rhs) == .orderedAscending
            }

        for sectionID in remainingSectionIDs {
            guard let sectionProjects = groupedProjectsBySectionID[sectionID],
                  !sectionProjects.isEmpty else {
                continue
            }
            sections.append(
                SidebarSection(
                    id: sectionID,
                    title: sectionID,
                    projects: sectionProjects
                )
            )
        }

        if let fallbackProjects = groupedProjectsBySectionID[Self.fallbackSectionID],
           !fallbackProjects.isEmpty {
            sections.append(
                SidebarSection(
                    id: Self.fallbackSectionID,
                    title: Self.fallbackSectionTitle,
                    projects: fallbackProjects
                )
            )
        }

        return sections
    }

    var orderedNodes: [WorkspaceNode] {
        projects.flatMap { project in
            var nodes = [
                WorkspaceNode(
                    selection: .project(project.id),
                    kind: .project,
                    parentProjectID: project.id,
                    title: project.name,
                    branchName: project.branch,
                    depth: 0,
                    hasChildren: !project.worktrees.isEmpty
                )
            ]

            guard !collapsedProjectIDs.contains(project.id) else {
                return nodes
            }

            nodes.append(contentsOf: project.worktrees.map {
                WorkspaceNode(
                    selection: .worktree($0.id),
                    kind: .worktree,
                    parentProjectID: project.id,
                    title: $0.name,
                    branchName: $0.branch,
                    depth: 1,
                    hasChildren: false
                )
            })
            return nodes
        }
    }

    func project(for selection: WorkspaceSelection) -> Project? {
        switch selection {
        case let .project(projectID):
            return projects.first { $0.id == projectID }
        case let .worktree(worktreeID):
            return projects.first { project in
                project.worktrees.contains { $0.id == worktreeID }
            }
        }
    }

    func project(id: UUID) -> Project? {
        projects.first { $0.id == id }
    }

    func worktree(for selection: WorkspaceSelection) -> Worktree? {
        guard case let .worktree(worktreeID) = selection else {
            return nil
        }

        return worktree(id: worktreeID)
    }

    func worktree(id: UUID) -> Worktree? {
        projects
            .flatMap(\.worktrees)
            .first { $0.id == id }
    }

    func projectForWorktree(id: UUID) -> Project? {
        projects.first { project in
            project.worktrees.contains(where: { $0.id == id })
        }
    }

    func path(for selection: WorkspaceSelection) -> String? {
        project(for: selection)?.path(for: selection)
    }

    func node(for selection: WorkspaceSelection) -> WorkspaceNode? {
        orderedNodes.first { $0.selection == selection }
    }

    static func fromImportedProjects(_ projects: [Project]) -> ProjectsState {
        ProjectsState(
            projects: projects,
            configuredSections: [],
            collapsedProjectIDs: [],
            collapsedSectionIDs: [],
            selection: projects.first.map { .project($0.id) } ?? .project(UUID()),
            nextProjectCount: projects.count + 1,
            nextWorktreeCount: 1
        )
    }
}

struct AgentState: Equatable {
    var sessions: [AgentSession]
    var selectedSessionID: UUID?
    var nextAgentCount: Int

    var selectedSession: AgentSession? {
        guard let selectedSessionID else {
            return nil
        }

        return sessions.first { $0.id == selectedSessionID }
    }

    mutating func selectSession(_ sessionID: UUID) {
        selectedSessionID = sessionID
    }

    func sessions(for selection: WorkspaceSelection) -> [AgentSession] {
        sessions.filter { $0.workspaceSelection == selection }
    }

    func firstSession(in selection: WorkspaceSelection) -> AgentSession? {
        sessions(for: selection).first
    }

    mutating func addAgent(
        to selection: WorkspaceSelection,
        launcherName: String,
        launchCommand: String,
        workingDirectory: String,
        kind: AgentKind = .unknown,
        expectsRichStatus: Bool = false
    ) -> AgentSession {
        let session = AgentSession(
            workspaceSelection: selection,
            name: "\(launcherName)-\(nextAgentCount)",
            kind: kind,
            status: .launching,
            launcherName: launcherName,
            launchCommand: launchCommand,
            workingDirectory: workingDirectory,
            terminalTitle: launcherName,
            lastActivity: "now",
            exitCode: nil,
            expectsRichStatus: expectsRichStatus
        )
        nextAgentCount += 1
        sessions.append(session)
        selectedSessionID = session.id
        return session
    }

    mutating func updateStatus(
        for sessionID: UUID,
        status: AgentSessionStatus,
        detail: String? = nil
    ) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }
        sessions[index].status = status
        sessions[index].statusDetail = detail
    }

    mutating func updateRichStatusMetadata(
        for sessionID: UUID,
        pluginVersion: String?
    ) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }
        sessions[index].hasRichStatus = true
        if let pluginVersion {
            sessions[index].pluginVersion = pluginVersion
        }
    }

    mutating func updateTerminalTitle(for sessionID: UUID, title: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }
        sessions[index].terminalTitle = title
        let resolvedName = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !resolvedName.isEmpty {
            sessions[index].name = resolvedName
        }
    }

    mutating func updateExitCode(for sessionID: UUID, exitCode: Int32?) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }
        sessions[index].exitCode = exitCode
        sessions[index].lastActivity = "just now"
    }

    mutating func removeSession(_ sessionID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }
        let removedSession = sessions[index]
        sessions.remove(at: index)

        if selectedSessionID == sessionID {
            let fallback = sessions.first { $0.workspaceSelection == removedSession.workspaceSelection }
            selectedSessionID = fallback?.id
        }
    }
}

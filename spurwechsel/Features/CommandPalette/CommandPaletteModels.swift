import Foundation

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

    mutating func presentTextInput(
        _ prompt: CommandBarTextPrompt,
        projectContextID: UUID? = nil,
        workspaceContext: WorkspaceSelection? = nil
    ) {
        isPresented = true
        mode = .textInput(prompt)
        self.projectContextID = projectContextID
        self.workspaceContext = workspaceContext
        textInput = ""
        notice = nil
        resetQuery()
    }

    mutating func presentPicker(
        title: String,
        items: [CommandBarPickerItem],
        emptyMessage: String,
        projectContextID: UUID? = nil,
        workspaceContext: WorkspaceSelection? = nil
    ) {
        isPresented = true
        mode = .picker(title: title, items: items, emptyMessage: emptyMessage)
        self.projectContextID = projectContextID
        self.workspaceContext = workspaceContext
        notice = nil
        resetQuery()
    }

    mutating func presentConfirmation(
        _ prompt: CommandBarConfirmationPrompt,
        projectContextID: UUID? = nil,
        workspaceContext: WorkspaceSelection? = nil
    ) {
        isPresented = true
        mode = .confirmation(prompt)
        self.projectContextID = projectContextID
        self.workspaceContext = workspaceContext
        notice = nil
        resetQuery()
    }

    mutating func presentError(
        _ text: String,
        projectContextID: UUID? = nil,
        workspaceContext: WorkspaceSelection? = nil,
        ensurePresented: Bool = false
    ) {
        if ensurePresented && !isPresented {
            presentCommandList(
                projectContextID: projectContextID,
                workspaceContext: workspaceContext
            )
        }
        notice = CommandBarNotice(text: text, isError: true)
        mode = .commandList
    }
}
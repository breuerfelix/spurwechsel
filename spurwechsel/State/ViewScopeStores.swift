import Combine
import Foundation
import GhosttyTerminal

@MainActor
class ViewScopeStoreBase: ObservableObject {
    private var cancellable: AnyCancellable?
    fileprivate let appStore: SpurwechselAppStore

    init(appStore: SpurwechselAppStore) {
        self.appStore = appStore
        cancellable = appStore.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }
}

@MainActor
final class CommandPaletteViewStore: ViewScopeStoreBase {
    var layout: AppLayoutState {
        get { appStore.layout }
        set { appStore.layout = newValue }
    }

    var commandBar: CommandBarState {
        get { appStore.commandBar }
        set { appStore.commandBar = newValue }
    }

    var filteredCommands: [CommandID] {
        appStore.filteredCommands
    }

    var filteredPickerItems: [CommandBarPickerItem] {
        appStore.filteredPickerItems
    }

    var theme: SpurTheme {
        appStore.theme
    }

    func shortcutBinding(for command: CommandID) -> ResolvedShortcutBinding? {
        appStore.shortcutBinding(for: command)
    }

    func closeCommandBar() {
        appStore.closeCommandBar()
    }

    func moveHighlightedCommand(_ offset: Int) {
        appStore.moveHighlightedCommand(offset)
    }

    func executeCommand(_ command: CommandID, projectContextID: UUID?) {
        appStore.executeCommand(command, projectContextID: projectContextID)
    }

    func updateCommandTextInput(_ text: String) {
        appStore.updateCommandTextInput(text)
    }

    func submitCommandBar() {
        appStore.submitCommandBar()
    }

    func cancelCommandBarConfirmation() {
        appStore.cancelCommandBarConfirmation()
    }

    func confirmCommandBarAction() {
        appStore.confirmCommandBarAction()
    }

    func updateCommandQuery(_ query: String) {
        appStore.updateCommandQuery(query)
    }
}

@MainActor
final class AgentSurfaceStore: ViewScopeStoreBase {
    var layout: AppLayoutState {
        get { appStore.layout }
        set { appStore.layout = newValue }
    }

    var projects: ProjectsState {
        get { appStore.projects }
        set { appStore.projects = newValue }
    }

    var theme: SpurTheme {
        appStore.theme
    }

    var terminalSurfacesAreForeground: Bool {
        appStore.terminalSurfacesAreForeground
    }

    var terminalTheme: TerminalTheme {
        appStore.terminalTheme
    }

    func resolvedAgentSession(
        sessionID: UUID?,
        in workspaceSelection: WorkspaceSelection
    ) -> AgentSession? {
        appStore.resolvedAgentSession(sessionID: sessionID, in: workspaceSelection)
    }

    func terminalController(for sessionID: UUID) -> AgentTerminalSessionController? {
        appStore.terminalController(for: sessionID)
    }
}

@MainActor
final class TerminalSurfaceStore: ViewScopeStoreBase {
    var layout: AppLayoutState {
        get { appStore.layout }
        set { appStore.layout = newValue }
    }

    var projects: ProjectsState {
        get { appStore.projects }
        set { appStore.projects = newValue }
    }

    var theme: SpurTheme {
        appStore.theme
    }

    var terminalSurfacesAreForeground: Bool {
        appStore.terminalSurfacesAreForeground
    }

    var terminalTheme: TerminalTheme {
        appStore.terminalTheme
    }

    func projectTerminalController(
        for selection: WorkspaceSelection
    ) -> LocalShellTerminalSessionController? {
        appStore.projectTerminalController(for: selection)
    }
}

@MainActor
final class EditorSurfaceStore: ViewScopeStoreBase {
    var theme: SpurTheme {
        appStore.theme
    }

    func editorSession(for workspaceID: String) -> EditorSessionState {
        appStore.editorSession(for: workspaceID) ?? EditorSessionState(
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

    func vscodeWebRuntime(forWorkspaceID workspaceID: String) -> EmbeddedWebViewRuntime? {
        appStore.vscodeWebRuntime(forWorkspaceID: workspaceID)
    }
}

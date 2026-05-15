import AppKit
import Foundation
import GhosttyTerminal
import SwiftUI

@MainActor
extension SpurwechselAppStore {
    func shutdownTerminalRuntimes() {
        coordinator.shutdownTerminalRuntimes()
    }

    func dismissConfigNotification() {
        coordinator.dismissConfigNotification()
    }

    func prepareForTermination() async -> AppTerminationSummary {
        await coordinator.prepareForTermination()
    }

    func requestApplicationQuit() {
        coordinator.requestApplicationQuit()
    }

    func handleWindowCloseRequest() -> Bool {
        coordinator.handleWindowCloseRequest()
    }

    func handleExternalURL(_ url: URL) {
        coordinator.handleExternalURL(url)
    }

    func setApplicationActive(_ isActive: Bool) {
        coordinator.setApplicationActive(isActive)
    }

    func setWindowKey(_ isKey: Bool) {
        coordinator.setWindowKey(isKey)
    }

    func recordFocusedSurfaceSlot(_ slot: SurfaceSlot) {
        coordinator.recordFocusedSurfaceSlot(slot)
    }

    var windowChromeState: WindowChromeState {
        shellStore.windowChrome
    }

    func setWindowChromeState(_ state: WindowChromeState) {
        shellStore.setWindowChrome(state)
    }

    func setTopBarFrameInWindow(_ frame: CGRect?) {
        shellStore.setTopBarFrameInWindow(frame)
    }

    var theme: SpurTheme { coordinator.theme }
    var terminalTheme: TerminalTheme { coordinator.terminalTheme }
    var terminalSurfacesAreForeground: Bool { coordinator.terminalSurfacesAreForeground }
    var mountedMainSurfaceID: SurfaceTabID? { coordinator.mountedMainSurfaceID }
    var mountedPreviewSurfaceID: SurfaceTabID? { coordinator.mountedPreviewSurfaceID }
    var selectedWorkspace: WorkspaceSelection { coordinator.selectedWorkspace }
    var selectedWorkspaceNode: WorkspaceNode? { coordinator.selectedWorkspaceNode }
    var groupedAgentNodes: [(WorkspaceNode, [AgentSession])] { coordinator.groupedAgentNodes }
    var selectedAgent: AgentSession? { coordinator.selectedAgent }

    func resolvedAgentSession(
        sessionID: UUID?,
        in workspaceSelection: WorkspaceSelection
    ) -> AgentSession? {
        coordinator.resolvedAgentSession(
            sessionID: sessionID,
            in: workspaceSelection
        )
    }

    func terminalController(for sessionID: UUID) -> AgentTerminalSessionController? {
        coordinator.terminalController(for: sessionID)
    }

    func surfaceTab(for id: SurfaceTabID) -> SurfaceTab? {
        coordinator.surfaceTab(for: id)
    }

    func projectTerminalController(
        for selection: WorkspaceSelection? = nil
    ) -> LocalShellTerminalSessionController? {
        coordinator.projectTerminalController(for: selection)
    }

    func vscodeWebRuntime(forWorkspaceID workspaceID: String) -> EmbeddedWebViewRuntime? {
        coordinator.vscodeWebRuntime(forWorkspaceID: workspaceID)
    }

    func editorSession(for workspaceID: String) -> EditorSessionState? {
        coordinator.editorSession(for: workspaceID)
    }

    var configuredAgents: [AgentConfigRecord] { coordinator.configuredAgents }
    var configuredDefaultAgent: AgentConfigRecord { coordinator.configuredDefaultAgent }
    var configuredShortcuts: [ResolvedShortcutBinding] { coordinator.configuredShortcuts }
    var filteredCommands: [CommandID] { coordinator.filteredCommands }
    var filteredPickerItems: [CommandBarPickerItem] { coordinator.filteredPickerItems }

    func shortcutBinding(for command: CommandID) -> ResolvedShortcutBinding? {
        coordinator.shortcutBinding(for: command)
    }

    func handleKeyDownEvent(
        _ event: NSEvent,
        focusedSurfaceSlot: SurfaceSlot?
    ) -> KeyDownInterceptResult {
        coordinator.handleKeyDownEvent(
            event,
            focusedSurfaceSlot: focusedSurfaceSlot
        )
    }

    @discardableResult
    func handleGlobalShortcutEvent(_ event: NSEvent) -> Bool {
        coordinator.handleGlobalShortcutEvent(event)
    }

    func dispatchShortcutCommand(_ command: CommandID) {
        coordinator.dispatchShortcutCommand(command)
    }

    func send(_ intent: AppIntent) {
        coordinator.handle(intent)
    }

    func toggleLeftSidebar() { coordinator.toggleLeftSidebar() }
    func toggleRightSidebar() { coordinator.toggleRightSidebar() }
    func togglePreview() { coordinator.togglePreview() }

    func setPreferredPreviewWidth(
        _ width: CGFloat,
        allowedRange: ClosedRange<CGFloat>
    ) {
        coordinator.setPreferredPreviewWidth(width, allowedRange: allowedRange)
    }

    func toggleTheme() { coordinator.toggleTheme() }
    func selectMainView(_ view: MainViewKind) { coordinator.selectMainView(view) }
    func selectPreviewView(_ view: PreviewViewKind) { coordinator.selectPreviewView(view) }
    func selectWorkspace(_ selection: WorkspaceSelection) { coordinator.selectWorkspace(selection) }
    func toggleProjectCollapse(_ projectID: UUID) { coordinator.toggleProjectCollapse(projectID) }

    func openCommandBar(
        projectContextID: UUID? = nil,
        workspaceContext: WorkspaceSelection? = nil
    ) {
        coordinator.openCommandBar(
            projectContextID: projectContextID,
            workspaceContext: workspaceContext
        )
    }

    func closeCommandBar(restorePreviousFocus: Bool = true) {
        coordinator.closeCommandBar(restorePreviousFocus: restorePreviousFocus)
    }

    func toggleCommandBar() { coordinator.toggleCommandBar() }
    func updateCommandQuery(_ query: String) { coordinator.updateCommandQuery(query) }
    func updateCommandTextInput(_ text: String) { coordinator.updateCommandTextInput(text) }
    func moveHighlightedCommand(_ offset: Int) { coordinator.moveHighlightedCommand(offset) }
    func submitCommandBar() { coordinator.submitCommandBar() }
    func executeHighlightedCommand() { coordinator.executeHighlightedCommand() }

    func executeCommand(
        _ command: CommandID,
        projectContextID: UUID? = nil,
        workspaceContext: WorkspaceSelection? = nil
    ) {
        coordinator.executeCommand(
            command,
            projectContextID: projectContextID,
            workspaceContext: workspaceContext
        )
    }

    func addProject() { coordinator.addProject() }
    func addWorktree(to projectID: UUID) { coordinator.addWorktree(to: projectID) }
    func cancelCommandBarConfirmation() { coordinator.cancelCommandBarConfirmation() }
    func confirmCommandBarAction() { coordinator.confirmCommandBarAction() }
    func addAgent(to selection: WorkspaceSelection) { coordinator.addAgent(to: selection) }
    func createDefaultAgent(workspaceContext: WorkspaceSelection?) {
        coordinator.createDefaultAgent(workspaceContext: workspaceContext)
    }
    func selectSession(_ sessionID: UUID) { coordinator.selectSession(sessionID) }
    func deleteAgent(sessionID: UUID) { coordinator.deleteAgent(sessionID: sessionID) }

    @discardableResult
    func importProjects(from urls: [URL]) -> Int {
        coordinator.importProjects(from: urls)
    }
}

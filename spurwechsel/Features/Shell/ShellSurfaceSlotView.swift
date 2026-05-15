import ComposableArchitecture
import GhosttyTerminal
import SwiftUI

struct ShellSurfaceSlotView: View {
    let slot: SurfaceSlot
    let surfaceID: SurfaceTabID?
    let shell: ShellFeature.State
    let isCommandPalettePresented: Bool
    let workbench: WorkbenchFeature.State
    let projects: ProjectsState
    let agents: AgentState
    let editorStore: StoreOf<EditorFeature>
    let theme: SpurTheme
    let terminalTheme: TerminalTheme
    let terminalSurfacesAreForeground: Bool
    let agentTerminalController: (UUID) -> AgentTerminalSessionController?
    let workspaceTerminalController: (WorkspaceSelection) -> LocalShellTerminalSessionController?
    let vscodeRuntime: (String) -> EmbeddedWebViewRuntime?
    let onSurfaceFocused: (SurfaceSlot) -> Void

    var body: some View {
        if let surfaceID,
           let tab = surfaceTab(for: surfaceID) {
            let isSelected = slot == .main || (slot == .preview && shell.layout.previewEnabled)
            surfaceContent(
                for: surfaceID,
                tab: tab,
                isSurfaceSelected: isSelected
            )
        } else if surfaceID != nil {
            SurfaceStateView(
                icon: "exclamationmark.triangle",
                title: "Surface unavailable",
                message: "Surface reference exists but no matching tab state found.",
                theme: theme,
                emphasis: .error,
                showsPanel: true
            )
            .accessibilityIdentifier(slot == .main ? "surface.main.unavailable" : "surface.preview.unavailable")
        } else if slot == .main && projects.projects.isEmpty {
            SurfaceStateView(
                icon: "folder.badge.plus",
                title: "No workspace imported",
                message: "Import a repository to start Agent, Terminal, or VSCode surfaces.",
                theme: theme,
                emphasis: .info,
                actionHint: "Command Bar: Add New Project",
                showsPanel: true
            )
            .accessibilityIdentifier("surface.main.empty")
        } else if slot == .preview {
            SurfaceStateView(
                icon: "rectangle.slash",
                title: "Preview unavailable",
                message: "Current preview view cannot mount for selected workspace.",
                theme: theme,
                emphasis: .neutral,
                actionHint: "Pick another preview view or switch workspace",
                showsPanel: true
            )
            .accessibilityIdentifier("surface.preview.empty")
        } else {
            SurfaceStateView(
                icon: "rectangle.stack",
                title: "No surface selected",
                message: "Select project, view, or session to mount surface.",
                theme: theme,
                emphasis: .neutral,
                showsPanel: true
            )
            .accessibilityIdentifier("surface.main.empty")
        }
    }

    @ViewBuilder
    private func surfaceContent(
        for surfaceID: SurfaceTabID,
        tab: SurfaceTab,
        isSurfaceSelected: Bool
    ) -> some View {
        // Command palette owns keyboard focus while visible; suppress deferred surface focus steals.
        let effectiveFocusRequest = isCommandPalettePresented ? nil : shell.surfaceFocusRequest

        switch surfaceID {
        case let .agentSession(sessionID):
            AgentMainView(
                sessionID: sessionID,
                workspaceSelection: tab.workspaceSelection,
                isSurfaceSelected: isSurfaceSelected,
                surfaceSlot: slot,
                focusRequest: effectiveFocusRequest,
                onSurfaceFocused: onSurfaceFocused,
                theme: theme,
                terminalTheme: terminalTheme,
                terminalSurfacesAreForeground: terminalSurfacesAreForeground,
                resolveSession: resolveSession(sessionID:in:),
                workspaceNode: projects.node(for:),
                terminalController: { sessionID in
                    agentTerminalController(sessionID)
                }
            )
        case .agentWorkspace:
            AgentMainView(
                sessionID: nil,
                workspaceSelection: tab.workspaceSelection,
                isSurfaceSelected: isSurfaceSelected,
                surfaceSlot: slot,
                focusRequest: effectiveFocusRequest,
                onSurfaceFocused: onSurfaceFocused,
                theme: theme,
                terminalTheme: terminalTheme,
                terminalSurfacesAreForeground: terminalSurfacesAreForeground,
                resolveSession: resolveSession(sessionID:in:),
                workspaceNode: projects.node(for:),
                terminalController: { sessionID in
                    agentTerminalController(sessionID)
                }
            )
        case .workspaceTerminal:
            ProjectTerminalMainView(
                workspaceSelection: tab.workspaceSelection,
                isSurfaceSelected: isSurfaceSelected,
                surfaceSlot: slot,
                focusRequest: effectiveFocusRequest,
                onSurfaceFocused: onSurfaceFocused,
                theme: theme,
                terminalTheme: terminalTheme,
                terminalSurfacesAreForeground: terminalSurfacesAreForeground,
                workspacePath: projects.path(for:),
                projectTerminalController: { selection in
                    workspaceTerminalController(selection)
                }
            )
        case let .vscodeWorkspace(workspaceID):
            VSCodeMainView(
                workspaceID: workspaceID,
                isSurfaceSelected: isSurfaceSelected,
                surfaceSlot: slot,
                focusRequest: effectiveFocusRequest,
                onSurfaceFocused: onSurfaceFocused,
                theme: theme,
                editorStore: editorStore,
                runtime: vscodeRuntime(workspaceID)
            )
        }
    }

    private func surfaceTab(for id: SurfaceTabID) -> SurfaceTab? {
        workbench.surfaceTabs.tabs.first(where: { $0.id == id })
    }

    private func resolveSession(
        sessionID: UUID?,
        in workspaceSelection: WorkspaceSelection
    ) -> AgentSession? {
        if let sessionID {
            return agents.sessions.first(where: { $0.id == sessionID })
        }

        if let selectedSession = agents.selectedSession,
           selectedSession.workspaceSelection == workspaceSelection {
            return selectedSession
        }

        return agents.firstSession(in: workspaceSelection)
    }
}

import GhosttyTerminal
import SwiftUI

struct ProjectTerminalMainView: View {
    private enum TerminalMainDensity {
        static let outerPadding: CGFloat = SpurSpacing.sm
        static let bodyCornerRadius: CGFloat = 12
    }

    let workspaceSelection: WorkspaceSelection
    let isSurfaceSelected: Bool
    let surfaceSlot: SurfaceSlot
    let focusRequest: SurfaceFocusRequest?
    let onSurfaceFocused: (SurfaceSlot) -> Void
    let theme: SpurTheme
    let terminalTheme: TerminalTheme
    let terminalSurfacesAreForeground: Bool
    let workspacePath: (WorkspaceSelection) -> String?
    let projectTerminalController: (WorkspaceSelection) -> LocalShellTerminalSessionController?

    private var terminalBackgroundColor: Color { theme.terminal }

    var body: some View {
        terminalBody
            .padding(TerminalMainDensity.outerPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .spurPanel(
                theme: theme,
                fill: terminalBackgroundColor,
                stroke: .clear,
                radius: SpurRadius.card,
                shadowOpacity: 0
            )
    }

    @ViewBuilder
    private var terminalBody: some View {
        Group {
            if let controller = projectTerminalController(workspaceSelection) {
                AgentTerminalHostView(
                    controller: controller,
                    terminalTheme: terminalTheme,
                    terminalBackgroundColor: terminalBackgroundColor,
                    isActive: isSurfaceSelected && terminalSurfacesAreForeground,
                    surfaceSlot: surfaceSlot,
                    focusRequest: focusRequest,
                    onSurfaceFocused: onSurfaceFocused
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(terminalBackgroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: TerminalMainDensity.bodyCornerRadius, style: .continuous))
                    .accessibilityIdentifier("project-terminal.surface")
            } else if workspacePath(workspaceSelection) == nil {
                SurfaceStateView(
                    icon: "terminal",
                    title: "No workspace selected",
                    message: "Select project or worktree to open terminal session.",
                    theme: theme,
                    emphasis: .info
                )
                    .accessibilityIdentifier("project-terminal.empty")
            } else {
                SurfaceStateView(
                    icon: "exclamationmark.triangle",
                    title: "Terminal unavailable",
                    message: "Could not attach terminal controller for selected workspace.",
                    theme: theme,
                    emphasis: .error
                )
                .accessibilityIdentifier("project-terminal.failure")
            }
        }
    }
}

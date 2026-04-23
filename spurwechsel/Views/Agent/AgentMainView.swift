import SwiftUI

struct AgentMainView: View {
    private enum AgentMainDensity {
        static let outerPadding: CGFloat = SpurSpacing.sm
        static let stackSpacing: CGFloat = SpurSpacing.sm
        static let railHorizontalPadding: CGFloat = 12
        static let railVerticalPadding: CGFloat = 7
        static let railMinHeight: CGFloat = 34
        static let railCornerRadius: CGFloat = 11
        static let bodyCornerRadius: CGFloat = 12
    }

    @ObservedObject var store: AgentSurfaceStore
    let sessionID: UUID?
    let workspaceSelection: WorkspaceSelection
    let isSurfaceSelected: Bool
    let surfaceSlot: SurfaceSlot
    let focusRequest: SurfaceFocusRequest?
    let onSurfaceFocused: (SurfaceSlot) -> Void

    init(
        store: AgentSurfaceStore,
        sessionID: UUID? = nil,
        workspaceSelection: WorkspaceSelection,
        isSurfaceSelected: Bool = true,
        surfaceSlot: SurfaceSlot = .main,
        focusRequest: SurfaceFocusRequest? = nil,
        onSurfaceFocused: @escaping (SurfaceSlot) -> Void = { _ in }
    ) {
        self.store = store
        self.sessionID = sessionID
        self.workspaceSelection = workspaceSelection
        self.isSurfaceSelected = isSurfaceSelected
        self.surfaceSlot = surfaceSlot
        self.focusRequest = focusRequest
        self.onSurfaceFocused = onSurfaceFocused
    }

    private var theme: SpurTheme { store.theme }
    private var terminalBackgroundColor: Color { theme.terminal }

    var body: some View {
        VStack(alignment: .leading, spacing: AgentMainDensity.stackSpacing) {
            if let session = resolvedSession {
                statusRail(for: session)
                sessionBody(for: session)
            } else {
                emptyRail
                SurfaceStateView(
                    icon: "sparkles.rectangle.stack",
                    title: "No active agent",
                    message: "Run Create Agent from command bar or sidebar plus button.",
                    theme: theme,
                    emphasis: .info,
                    actionHint: "Command Bar: Create Agent"
                )
            }
        }
        .padding(AgentMainDensity.outerPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .spurPanel(
            theme: theme,
            fill: terminalBackgroundColor,
            stroke: .clear,
            radius: SpurRadius.card,
            shadowOpacity: 0
        )
    }

    private func sessionBody(for session: AgentSession) -> some View {
        Group {
            if let controller = store.terminalController(for: session.id) {
                AgentTerminalHostView(
                    controller: controller,
                    terminalTheme: store.terminalTheme,
                    terminalBackgroundColor: terminalBackgroundColor,
                    isActive: isSurfaceSelected
                        && store.terminalSurfacesAreForeground,
                    surfaceSlot: surfaceSlot,
                    focusRequest: focusRequest,
                    onSurfaceFocused: onSurfaceFocused
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(terminalBackgroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: AgentMainDensity.bodyCornerRadius, style: .continuous))
                    .accessibilityIdentifier("agent.terminal")
            } else {
                SurfaceStateView(
                    icon: "terminal",
                    title: "Session not running",
                    message: "Launch an agent from this workspace to start terminal session.",
                    theme: theme,
                    emphasis: .warning
                )
            }
        }
    }

    private var resolvedSession: AgentSession? {
        guard let sessionID else { return nil }
        return store.resolvedAgentSession(
            sessionID: sessionID,
            in: workspaceSelection
        )
    }

    private func statusRail(for session: AgentSession) -> some View {
        HStack(spacing: SpurSpacing.sm) {
            HStack(spacing: SpurSpacing.sm) {
                Text(session.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.foreground)
                    .lineLimit(1)
                    .accessibilityIdentifier("agent.header.session-name")

                if let workspace = store.projects.node(for: session.workspaceSelection) {
                    Text("•")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.foregroundDim)
                    Text(workspace.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.foregroundMuted)
                        .lineLimit(1)
                    Text(workspace.branchName)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.foregroundDim)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: SpurSpacing.sm) {
                Label(session.launcherName, systemImage: "cpu")
                Label(session.lastActivity, systemImage: "clock")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(theme.foregroundMuted)

            StatusBadgeView(status: session.status, theme: theme)
                .fixedSize()
        }
        .padding(.horizontal, AgentMainDensity.railHorizontalPadding)
        .padding(.vertical, AgentMainDensity.railVerticalPadding)
        .frame(minHeight: AgentMainDensity.railMinHeight)
        .background(theme.panelMuted)
        .overlay(
            RoundedRectangle(cornerRadius: AgentMainDensity.railCornerRadius, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AgentMainDensity.railCornerRadius, style: .continuous))
    }

    private var emptyRail: some View {
        HStack(spacing: SpurSpacing.sm) {
            Text("Agent")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.foreground)
            Spacer(minLength: 0)
            Text("Idle")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.foregroundDim)
        }
        .padding(.horizontal, AgentMainDensity.railHorizontalPadding)
        .padding(.vertical, AgentMainDensity.railVerticalPadding)
        .frame(minHeight: AgentMainDensity.railMinHeight)
        .background(theme.panelMuted)
        .overlay(
            RoundedRectangle(cornerRadius: AgentMainDensity.railCornerRadius, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AgentMainDensity.railCornerRadius, style: .continuous))
    }

}

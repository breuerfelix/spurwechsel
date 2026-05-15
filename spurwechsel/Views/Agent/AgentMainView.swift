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
                    if !workspace.branchName.isEmpty {
                        Text(workspace.branchName)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.foregroundDim)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: SpurSpacing.sm) {
                Label(session.launcherName, systemImage: "cpu")
                Label(session.lastActivity, systemImage: "clock")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(theme.foregroundMuted)

            if session.showsWarpPluginWarning {
                WarpPluginWarningBadge(theme: theme) { text in
                    store.terminalController(for: session.id)?.sendText(text)
                }
                    .fixedSize()
            }

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

private struct WarpPluginWarningBadge: View {
    let theme: SpurTheme
    let onInsertInstructions: (String) -> Void
    @State private var showsPopover = false

    var body: some View {
        Button {
            showsPopover.toggle()
        } label: {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.warning)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(theme.warning.opacity(0.14))
            .overlay(
                Capsule()
                    .stroke(theme.warning.opacity(0.38), lineWidth: 1)
            )
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                showsPopover = true
            }
        }
        .popover(isPresented: $showsPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: SpurSpacing.sm) {
                Text("OpenCode rich status unavailable")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Install Warp OpenCode plugin, then restart this agent.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.foregroundMuted)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("1. Add `@warp-dot-dev/opencode-warp` to `plugin` in `opencode.json`.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.foregroundMuted)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("2. Configure workspace `./opencode.json` or global `~/.config/opencode/opencode.json`.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.foregroundMuted)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("3. Restart agent to enable rich status events.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.foregroundMuted)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    onInsertInstructions(Self.globalInstallInstructions)
                    showsPopover = false
                } label: {
                    Label("Insert Instructions Into Agent", systemImage: "arrow.down.doc")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.warning)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(theme.warning.opacity(0.12))
                        .overlay(
                            Capsule()
                                .stroke(theme.warning.opacity(0.36), lineWidth: 1)
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .focusable(false)
            }
            .frame(width: 340, alignment: .leading)
            .padding(12)
            .spurPanel(
                theme: theme,
                fill: theme.panel,
                stroke: theme.border,
                radius: SpurRadius.card,
                shadowOpacity: 0.2
            )
            .accessibilityIdentifier("agent.header.warp-warning.popover")
        }
        .accessibilityIdentifier("agent.header.warp-warning.badge")
    }

    private static let globalInstallInstructions = """
    Install Warp OpenCode plugin globally for rich status events.

    Steps:
    1. Ensure directory exists: ~/.config/opencode
    2. Edit file: ~/.config/opencode/opencode.json
    3. In JSON key "plugin" (array), add string "@warp-dot-dev/opencode-warp".
    4. Preserve existing plugin entries. Do not remove unrelated config.
    5. If "plugin" key missing, create it as array and include "@warp-dot-dev/opencode-warp".
    6. Save valid JSON.

    After installation:
    - Tell me exactly what changed.
    - Remind me to restart OpenCode agent session in Spurwechsel so rich status becomes active.
    """
}

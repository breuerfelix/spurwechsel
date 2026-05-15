import SwiftUI

private enum AgentSidebarDensity {
    static let sidebarSpacing: CGFloat = SpurSpacing.sm
    static let titleTopPadding: CGFloat = SpurSpacing.md
    static let titleHorizontalPadding: CGFloat = SpurSpacing.md
    static let contentHorizontalPadding: CGFloat = SpurSpacing.xs
    static let contentBottomPadding: CGFloat = SpurSpacing.xs
    static let groupVerticalPadding: CGFloat = SpurSpacing.sm
    static let groupHeaderMinHeight: CGFloat = 24
    static let groupHorizontalPadding: CGFloat = 10
    static let groupCornerRadius: CGFloat = 12
    static let groupRowSpacing: CGFloat = SpurSpacing.xs
    static let rowVerticalPadding: CGFloat = 8
    static let rowHorizontalPadding: CGFloat = 10
    static let rowCornerRadius: CGFloat = 10
    static let hoverButtonSize: CGFloat = 22
    static let hoverIconSize: CGFloat = 10
}

struct ContextSidebarView: View {
    let projects: ProjectsState
    let agents: AgentState
    let selectedMainView: MainViewKind
    let theme: SpurTheme
    let showsBranchNames: Bool
    let addAgent: (WorkspaceSelection) -> Void
    let selectSession: (UUID) -> Void

    private var groupedAgentNodes: [(WorkspaceNode, [AgentSession])] {
        let sessionsBySelection = Dictionary(grouping: agents.sessions, by: \.workspaceSelection)
        let selectedSelection = projects.selection

        var visibleNodes = projects.orderedNodes.filter { node in
            let hasAgents = !(sessionsBySelection[node.selection] ?? []).isEmpty
            return hasAgents || node.selection == selectedSelection
        }

        if !visibleNodes.contains(where: { $0.selection == selectedSelection }),
           let selectedNode = workspaceNode(for: selectedSelection) {
            visibleNodes.append(selectedNode)
        }

        return visibleNodes.map { node in
            (node, sessionsBySelection[node.selection] ?? [])
        }
    }

    private func workspaceNode(for selection: WorkspaceSelection) -> WorkspaceNode? {
        switch selection {
        case let .project(projectID):
            guard let project = projects.project(id: projectID) else {
                return nil
            }
            return WorkspaceNode(
                selection: .project(project.id),
                kind: .project,
                parentProjectID: project.id,
                title: project.name,
                branchName: project.branch,
                depth: 0,
                hasChildren: !project.worktrees.isEmpty
            )
        case let .worktree(worktreeID):
            guard let project = projects.projectForWorktree(id: worktreeID),
                  let worktree = project.worktrees.first(where: { $0.id == worktreeID }) else {
                return nil
            }
            return WorkspaceNode(
                selection: .worktree(worktree.id),
                kind: .worktree,
                parentProjectID: project.id,
                title: worktree.name,
                branchName: worktree.branch,
                depth: 1,
                hasChildren: false
            )
        }
    }

    var body: some View {
        if selectedMainView == .agent {
            AgentSidebarView(
                theme: theme,
                groupedAgentNodes: groupedAgentNodes,
                selectedWorkspaceSelection: projects.selection,
                selectedSessionID: agents.selectedSessionID,
                showsBranchNames: showsBranchNames,
                addAgent: addAgent,
                selectSession: selectSession
            )
                .frame(maxHeight: .infinity)
        } else {
            Color.clear
        }
    }
}

private struct AgentSidebarView: View {
    let theme: SpurTheme
    let groupedAgentNodes: [(WorkspaceNode, [AgentSession])]
    let selectedWorkspaceSelection: WorkspaceSelection
    let selectedSessionID: UUID?
    let showsBranchNames: Bool
    let addAgent: (WorkspaceSelection) -> Void
    let selectSession: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSidebarDensity.sidebarSpacing) {
            Text("Agents")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.foreground)
                .padding(.horizontal, AgentSidebarDensity.titleHorizontalPadding)
                .padding(.top, AgentSidebarDensity.titleTopPadding)

            ScrollView {
                VStack(alignment: .leading, spacing: AgentSidebarDensity.sidebarSpacing) {
                    ForEach(groupedAgentNodes, id: \.0.id) { node, sessions in
                        AgentGroupView(
                            node: node,
                            sessions: sessions,
                            theme: theme,
                            isSelected: node.selection == selectedWorkspaceSelection,
                            selectedSessionID: selectedSessionID,
                            showsBranchNames: showsBranchNames,
                            addAgent: addAgent,
                            selectSession: selectSession
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AgentSidebarDensity.contentHorizontalPadding)
                .padding(.bottom, AgentSidebarDensity.contentBottomPadding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.vertical, AgentSidebarDensity.contentHorizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct AgentGroupView: View {
    let node: WorkspaceNode
    let sessions: [AgentSession]
    let theme: SpurTheme
    let isSelected: Bool
    let selectedSessionID: UUID?
    let showsBranchNames: Bool
    let addAgent: (WorkspaceSelection) -> Void
    let selectSession: (UUID) -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSidebarDensity.groupRowSpacing) {
            HStack {
                Text(node.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.foreground)
                Spacer()
                hoverPlusSlot
                if showsBranchNames, !node.branchName.isEmpty {
                    Text(node.branchName)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.foregroundDim)
                }
            }
            .padding(.horizontal, AgentSidebarDensity.groupHorizontalPadding)
            .frame(minHeight: AgentSidebarDensity.groupHeaderMinHeight)
            .onHover { hovering in
                isHovering = hovering
            }

            ForEach(sessions) { session in
                AgentRowView(
                    session: session,
                    theme: theme,
                    isSelected: selectedSessionID == session.id,
                    selectSession: selectSession
                )
            }
        }
        .padding(.vertical, AgentSidebarDensity.groupVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: AgentSidebarDensity.groupCornerRadius, style: .continuous)
                .fill(theme.panelMuted)
                .overlay(
                    RoundedRectangle(cornerRadius: AgentSidebarDensity.groupCornerRadius, style: .continuous)
                        .fill(isSelected ? theme.selection.opacity(0.12) : Color.clear)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: AgentSidebarDensity.groupCornerRadius, style: .continuous)
                .stroke(isSelected ? theme.selection.opacity(0.32) : Color.clear, lineWidth: isSelected ? 1 : 0)
        )
    }

    @ViewBuilder
    private var hoverPlusSlot: some View {
        if isHovering {
            GhostActionButton(
                systemName: "plus",
                title: "Create agent",
                theme: theme,
                buttonSize: AgentSidebarDensity.hoverButtonSize,
                iconSize: AgentSidebarDensity.hoverIconSize,
                cornerRadius: 7,
                accessibilityID: "agents.add.\(node.title.accessibilitySlug)"
            ) {
                addAgent(node.selection)
            }
        } else {
            Color.clear
                .frame(width: AgentSidebarDensity.hoverButtonSize, height: AgentSidebarDensity.hoverButtonSize)
        }
    }
}

private struct AgentRowView: View {
    let session: AgentSession
    let theme: SpurTheme
    let isSelected: Bool
    let selectSession: (UUID) -> Void

    var body: some View {
        Button {
            selectSession(session.id)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: SpurSpacing.xs) {
                    Text(session.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(theme.foreground)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text(session.lastActivity)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(theme.foregroundDim)
                        .lineLimit(1)
                }

                HStack(spacing: SpurSpacing.xs) {
                    Text(session.status.title.lowercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.statusColor(for: session.status))

                    Text(primaryModelName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.foregroundMuted)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, AgentSidebarDensity.rowHorizontalPadding)
            .padding(.vertical, AgentSidebarDensity.rowVerticalPadding)
            .background(
                RoundedRectangle(cornerRadius: AgentSidebarDensity.rowCornerRadius, style: .continuous)
                    .fill(isSelected ? theme.selection : theme.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AgentSidebarDensity.rowCornerRadius, style: .continuous)
                    .stroke(Color.clear, lineWidth: 0)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, AgentSidebarDensity.groupHorizontalPadding)
        .accessibilityIdentifier("agents.session.\(session.id.uuidString)")
    }

    private var primaryModelName: String {
        session.launcherName
    }
}

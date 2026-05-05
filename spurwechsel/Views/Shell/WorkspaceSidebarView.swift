import SwiftUI

private enum WorkspaceSidebarDensity {
    static let sidebarSpacing: CGFloat = SpurSpacing.lg
    static let titleHorizontalPadding: CGFloat = SpurSpacing.md
    static let contentHorizontalPadding: CGFloat = SpurSpacing.xs
    static let contentBottomPadding: CGFloat = SpurSpacing.xs
    static let sidebarTopPadding: CGFloat = SpurSpacing.sm
    static let sidebarBottomPadding: CGFloat = SpurSpacing.sm
}

struct WorkspaceSidebarView: View {
    @ObservedObject var shellStore: ShellStore
    @ObservedObject var workspaceStore: WorkspaceStore
    let executeCommand: (CommandID) -> Void
    let toggleTheme: () -> Void
    let selectWorkspace: (WorkspaceSelection) -> Void
    let addWorktree: (UUID) -> Void
    let toggleProjectCollapse: (UUID) -> Void

    private var theme: SpurTheme { shellStore.theme }

    var body: some View {
        VStack(alignment: .leading, spacing: WorkspaceSidebarDensity.sidebarSpacing) {
            WorkspaceSidebarHeader(executeCommand: executeCommand, theme: theme)

            ScrollView {
                VStack(alignment: .leading, spacing: SpurSpacing.sm) {
                    ForEach(workspaceStore.projects.projects) { project in
                        ProjectGroupView(
                            workspaceStore: workspaceStore,
                            project: project,
                            theme: theme,
                            selectWorkspace: selectWorkspace,
                            addWorktree: addWorktree,
                            toggleProjectCollapse: toggleProjectCollapse
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, WorkspaceSidebarDensity.contentHorizontalPadding)
                .padding(.bottom, WorkspaceSidebarDensity.contentBottomPadding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack {
                Text("Theme")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.foregroundMuted)
                Spacer()
                ThemeToggleView(theme: theme, selectedMode: shellStore.layout.themeMode) {
                    toggleTheme()
                }
            }
            .padding(.horizontal, WorkspaceSidebarDensity.titleHorizontalPadding)
            .padding(.bottom, WorkspaceSidebarDensity.sidebarBottomPadding)
        }
        .padding(.top, WorkspaceSidebarDensity.sidebarTopPadding)
        .padding(.bottom, WorkspaceSidebarDensity.sidebarBottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct WorkspaceSidebarHeader: View {
    let executeCommand: (CommandID) -> Void
    let theme: SpurTheme

    @State private var isHovering = false

    var body: some View {
        HStack {
            Text("Projects")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.foreground)
            Spacer()
            headerHoverPlusSlot
        }
        .padding(.horizontal, WorkspaceSidebarDensity.titleHorizontalPadding)
        .frame(minHeight: 28)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    @ViewBuilder
    private var headerHoverPlusSlot: some View {
        if isHovering {
            GhostActionButton(
                systemName: "plus",
                title: "Add project",
                theme: theme,
                buttonSize: 20,
                iconSize: 9,
                cornerRadius: 6,
                accessibilityID: "projects.add"
            ) {
                executeCommand(.addProject)
            }
        } else {
            Color.clear
                .frame(width: 20, height: 20)
        }
    }
}

private struct ProjectGroupView: View {
    @ObservedObject var workspaceStore: WorkspaceStore
    let project: Project
    let theme: SpurTheme
    let selectWorkspace: (WorkspaceSelection) -> Void
    let addWorktree: (UUID) -> Void
    let toggleProjectCollapse: (UUID) -> Void

    private var isCollapsed: Bool {
        workspaceStore.projects.collapsedProjectIDs.contains(project.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SpurSpacing.xs) {
            ProjectRowView(
                workspaceStore: workspaceStore,
                project: project,
                theme: theme,
                isCollapsed: isCollapsed,
                selectWorkspace: selectWorkspace,
                addWorktree: addWorktree,
                toggleProjectCollapse: toggleProjectCollapse
            )

            if !isCollapsed {
                ForEach(project.worktrees) { worktree in
                    WorktreeRowView(
                        workspaceStore: workspaceStore,
                        project: project,
                        worktree: worktree,
                        theme: theme,
                        selectWorkspace: selectWorkspace
                    )
                        .padding(.leading, 18)
                }
            }
        }
    }
}

private struct ProjectRowView: View {
    @ObservedObject var workspaceStore: WorkspaceStore
    let project: Project
    let theme: SpurTheme
    let isCollapsed: Bool
    let selectWorkspace: (WorkspaceSelection) -> Void
    let addWorktree: (UUID) -> Void
    let toggleProjectCollapse: (UUID) -> Void

    @State private var isHovering = false

    private var isSelected: Bool {
        workspaceStore.projects.selection == .project(project.id)
    }

    var body: some View {
        HStack(spacing: SpurSpacing.md) {
            HStack(spacing: SpurSpacing.md) {
                Text(project.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? theme.foreground : theme.foregroundMuted)

                Spacer(minLength: 0)

                hoverPlusSlot

                Text(project.branch)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(isSelected ? theme.foreground : theme.foregroundDim)
                    .accessibilityIdentifier("projects.project-branch.\(project.name.accessibilitySlug)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !project.worktrees.isEmpty {
                HitboxIconButton(
                    systemName: isCollapsed ? "chevron.right" : "chevron.down",
                    title: isCollapsed ? "Show worktrees" : "Hide worktrees",
                    theme: theme,
                    hitboxSize: 16,
                    iconSize: 10,
                    accessibilityID: "projects.collapse.\(project.name.accessibilitySlug)"
                ) {
                    toggleProjectCollapse(project.id)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? theme.selection : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectWorkspace(.project(project.id))
        }
        .accessibilityIdentifier("projects.project.\(project.name.accessibilitySlug)")
        .onHover { hovering in
            isHovering = hovering
        }
    }

    @ViewBuilder
    private var hoverPlusSlot: some View {
        if isHovering {
            GhostActionButton(
                systemName: "plus",
                title: "Create worktree",
                theme: theme,
                buttonSize: 20,
                iconSize: 9,
                cornerRadius: 6,
                accessibilityID: "projects.create-worktree.\(project.name.accessibilitySlug)"
            ) {
                addWorktree(project.id)
            }
        } else {
            Color.clear
                .frame(width: 20, height: 20)
        }
    }
}

private struct WorktreeRowView: View {
    @ObservedObject var workspaceStore: WorkspaceStore
    let project: Project
    let worktree: Worktree
    let theme: SpurTheme
    let selectWorkspace: (WorkspaceSelection) -> Void

    private var isSelected: Bool {
        workspaceStore.projects.selection == .worktree(worktree.id)
    }

    var body: some View {
        HStack(spacing: SpurSpacing.md) {
            Text(worktree.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? theme.foreground : theme.foregroundMuted)
            Spacer(minLength: 0)
            Text(worktree.branch)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(isSelected ? theme.foreground : theme.foregroundDim)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? theme.selection : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectWorkspace(.worktree(worktree.id))
        }
        .accessibilityIdentifier("projects.worktree.\(worktree.name.accessibilitySlug)")
    }
}

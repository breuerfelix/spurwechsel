import ComposableArchitecture
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
    let store: StoreOf<WorkspaceFeature>
    let projects: ProjectsState
    let theme: SpurTheme
    let selectedThemeMode: ThemeMode
    let showsBranchNames: Bool
    let executeCommand: (CommandID) -> Void
    let toggleTheme: () -> Void
    let addWorktree: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WorkspaceSidebarDensity.sidebarSpacing) {
            WorkspaceSidebarHeader(executeCommand: executeCommand, theme: theme)

            ScrollView {
                VStack(alignment: .leading, spacing: SpurSpacing.sm) {
                    let sections = projects.sidebarSections
                    if sections.count == 1, let onlySection = sections.first {
                        ForEach(onlySection.projects) { project in
                            ProjectGroupView(
                                projects: projects,
                                project: project,
                                theme: theme,
                                showsBranchNames: showsBranchNames,
                                selectWorkspace: { store.send(.selectWorkspace($0)) },
                                addWorktree: addWorktree,
                                toggleProjectCollapse: { store.send(.toggleProjectCollapse($0)) }
                            )
                        }
                    } else {
                        ForEach(sections) { section in
                            SectionGroupView(
                                projects: projects,
                                section: section,
                                theme: theme,
                                showsBranchNames: showsBranchNames,
                                selectWorkspace: { store.send(.selectWorkspace($0)) },
                                addWorktree: addWorktree,
                                toggleProjectCollapse: { store.send(.toggleProjectCollapse($0)) },
                                toggleSectionCollapse: { store.send(.toggleSectionCollapse($0)) }
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, WorkspaceSidebarDensity.contentHorizontalPadding)
                .padding(.bottom, WorkspaceSidebarDensity.contentBottomPadding)
            }
            .autoHidingOverlayScrollIndicators()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack {
                Text("Theme")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.foregroundMuted)
                Spacer()
                ThemeToggleView(theme: theme, selectedMode: selectedThemeMode) {
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

private struct SectionGroupView: View {
    let projects: ProjectsState
    let section: ProjectsState.SidebarSection
    let theme: SpurTheme
    let showsBranchNames: Bool
    let selectWorkspace: (WorkspaceSelection) -> Void
    let addWorktree: (UUID) -> Void
    let toggleProjectCollapse: (UUID) -> Void
    let toggleSectionCollapse: (String) -> Void

    private var isCollapsed: Bool {
        projects.collapsedSectionIDs.contains(section.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SpurSpacing.xs) {
            SectionRowView(
                section: section,
                theme: theme,
                isCollapsed: isCollapsed,
                toggleSectionCollapse: toggleSectionCollapse
            )

            if !isCollapsed {
                VStack(alignment: .leading, spacing: SpurSpacing.xs) {
                    ForEach(section.projects) { project in
                        ProjectGroupView(
                            projects: projects,
                            project: project,
                            theme: theme,
                            showsBranchNames: showsBranchNames,
                            selectWorkspace: selectWorkspace,
                            addWorktree: addWorktree,
                            toggleProjectCollapse: toggleProjectCollapse
                        )
                    }
                }
            }
        }
    }
}

private struct SectionRowView: View {
    let section: ProjectsState.SidebarSection
    let theme: SpurTheme
    let isCollapsed: Bool
    let toggleSectionCollapse: (String) -> Void

    private var sectionLabel: String {
        isCollapsed ? "\(section.title) (\(section.projectCount))" : section.title
    }

    var body: some View {
        HStack(spacing: SpurSpacing.xs) {
            sectionLine
            Text(sectionLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isCollapsed ? theme.foregroundDim : theme.foregroundMuted)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
                .padding(.horizontal, 5)
            sectionLine
        }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .onTapGesture {
                toggleSectionCollapse(section.id)
            }
            .accessibilityIdentifier("projects.section.\(section.id.accessibilitySlug)")
    }

    private var sectionLine: some View {
        Rectangle()
            .fill(isCollapsed ? theme.border : theme.borderStrong)
            .frame(maxWidth: .infinity, minHeight: 1, maxHeight: 1)
            .layoutPriority(-1)
    }
}

private struct ProjectGroupView: View {
    let projects: ProjectsState
    let project: Project
    let theme: SpurTheme
    let showsBranchNames: Bool
    let selectWorkspace: (WorkspaceSelection) -> Void
    let addWorktree: (UUID) -> Void
    let toggleProjectCollapse: (UUID) -> Void

    private var isCollapsed: Bool {
        projects.collapsedProjectIDs.contains(project.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SpurSpacing.xs) {
            ProjectRowView(
                projects: projects,
                project: project,
                theme: theme,
                isCollapsed: isCollapsed,
                showsBranchNames: showsBranchNames,
                selectWorkspace: selectWorkspace,
                addWorktree: addWorktree,
                toggleProjectCollapse: toggleProjectCollapse
            )

            if !isCollapsed {
                ForEach(project.worktrees) { worktree in
                    WorktreeRowView(
                        projects: projects,
                        project: project,
                        worktree: worktree,
                        theme: theme,
                        showsBranchNames: showsBranchNames,
                        selectWorkspace: selectWorkspace
                    )
                        .padding(.leading, 18)
                }
            }
        }
    }
}

private struct ProjectRowView: View {
    let projects: ProjectsState
    let project: Project
    let theme: SpurTheme
    let isCollapsed: Bool
    let showsBranchNames: Bool
    let selectWorkspace: (WorkspaceSelection) -> Void
    let addWorktree: (UUID) -> Void
    let toggleProjectCollapse: (UUID) -> Void

    @State private var isHovering = false

    private var isSelected: Bool {
        projects.selection == .project(project.id)
    }

    var body: some View {
        HStack(spacing: SpurSpacing.md) {
            HStack(spacing: SpurSpacing.md) {
                Text(project.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? theme.foreground : theme.foregroundMuted)

                Spacer(minLength: 0)

                hoverPlusSlot

                if showsBranchNames, project.isGitRepository {
                    Text(project.branch)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(isSelected ? theme.foreground : theme.foregroundDim)
                        .accessibilityIdentifier("projects.project-branch.\(project.name.accessibilitySlug)")
                }
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
        if isHovering, project.isGitRepository {
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
    let projects: ProjectsState
    let project: Project
    let worktree: Worktree
    let theme: SpurTheme
    let showsBranchNames: Bool
    let selectWorkspace: (WorkspaceSelection) -> Void

    private var isSelected: Bool {
        projects.selection == .worktree(worktree.id)
    }

    var body: some View {
        HStack(spacing: SpurSpacing.md) {
            Text(worktree.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? theme.foreground : theme.foregroundMuted)
            Spacer(minLength: 0)
            if showsBranchNames {
                Text(worktree.branch)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(isSelected ? theme.foreground : theme.foregroundDim)
            }
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

import Foundation

struct ProjectsState: Equatable {
    static let fallbackSectionID = ProjectSectionRecord.fallbackID
    static let fallbackSectionTitle = ProjectSectionRecord.fallbackID

    struct SidebarSection: Identifiable, Equatable {
        let id: String
        let title: String
        let projects: [Project]

        var projectCount: Int { projects.count }
    }

    var projects: [Project]
    var configuredSections: [ProjectSectionRecord]
    var collapsedProjectIDs: Set<UUID>
    var collapsedSectionIDs: Set<String>
    var selection: WorkspaceSelection
    var nextProjectCount: Int
    var nextWorktreeCount: Int

    mutating func toggleProjectCollapse(_ projectID: UUID) {
        if collapsedProjectIDs.contains(projectID) {
            collapsedProjectIDs.remove(projectID)
        } else {
            collapsedProjectIDs.insert(projectID)
        }
    }

    mutating func select(_ selection: WorkspaceSelection) {
        self.selection = selection
    }

    mutating func toggleSectionCollapse(_ sectionID: String) {
        if collapsedSectionIDs.contains(sectionID) {
            collapsedSectionIDs.remove(sectionID)
        } else {
            collapsedSectionIDs.insert(sectionID)
        }
    }

    mutating func replaceProjects(
        _ projects: [Project],
        configuredSections: [ProjectSectionRecord]
    ) {
        let previousSelection = selection

        self.projects = projects
        self.configuredSections = configuredSections
        collapsedProjectIDs = collapsedProjectIDs.intersection(Set(projects.map(\.id)))
        collapsedSectionIDs = collapsedSectionIDs.intersection(Set(sidebarSections.map(\.id)))
        nextProjectCount = max(nextProjectCount, projects.count + 1)

        if projects.contains(where: { $0.contains(previousSelection) }) {
            selection = previousSelection
        } else if let firstProject = projects.first {
            selection = .project(firstProject.id)
        } else {
            selection = .project(UUID())
        }
    }

    mutating func addProject() -> Project {
        let project = Project(
            name: "workspace-\(nextProjectCount)",
            branch: "feature/idea-\(nextProjectCount)"
        )
        nextProjectCount += 1
        projects.append(project)
        selection = .project(project.id)
        collapsedProjectIDs.remove(project.id)
        return project
    }

    mutating func addWorktree(to projectID: UUID) -> Worktree? {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            return nil
        }

        let worktree = Worktree(
            name: "explore-\(nextWorktreeCount)",
            branch: "wt/explore-\(nextWorktreeCount)"
        )
        nextWorktreeCount += 1
        projects[projectIndex].worktrees.append(worktree)
        collapsedProjectIDs.remove(projectID)
        selection = .worktree(worktree.id)
        return worktree
    }

    var sidebarSections: [SidebarSection] {
        var groupedProjectsBySectionID: [String: [Project]] = [:]
        for project in projects {
            let sectionIDs = project.sectionIDs.isEmpty
                ? [Self.fallbackSectionID]
                : project.sectionIDs
            for sectionID in sectionIDs {
                groupedProjectsBySectionID[sectionID, default: []].append(project)
            }
        }

        var sections: [SidebarSection] = []
        var consumedSectionIDs = Set<String>()

        for configuredSection in configuredSections {
            guard let sectionProjects = groupedProjectsBySectionID[configuredSection.id],
                  !sectionProjects.isEmpty else {
                continue
            }
            consumedSectionIDs.insert(configuredSection.id)
            sections.append(
                SidebarSection(
                    id: configuredSection.id,
                    title: configuredSection.displayName,
                    projects: sectionProjects
                )
            )
        }

        let remainingSectionIDs = groupedProjectsBySectionID.keys
            .filter { $0 != Self.fallbackSectionID && !consumedSectionIDs.contains($0) }
            .sorted { lhs, rhs in
                lhs.localizedStandardCompare(rhs) == .orderedAscending
            }

        for sectionID in remainingSectionIDs {
            guard let sectionProjects = groupedProjectsBySectionID[sectionID],
                  !sectionProjects.isEmpty else {
                continue
            }
            sections.append(
                SidebarSection(
                    id: sectionID,
                    title: sectionID,
                    projects: sectionProjects
                )
            )
        }

        if let fallbackProjects = groupedProjectsBySectionID[Self.fallbackSectionID],
           !fallbackProjects.isEmpty {
            sections.append(
                SidebarSection(
                    id: Self.fallbackSectionID,
                    title: Self.fallbackSectionTitle,
                    projects: fallbackProjects
                )
            )
        }

        return sections
    }

    var orderedNodes: [WorkspaceNode] {
        projects.flatMap { project in
            var nodes = [
                WorkspaceNode(
                    selection: .project(project.id),
                    kind: .project,
                    parentProjectID: project.id,
                    title: project.name,
                    branchName: project.branch,
                    depth: 0,
                    hasChildren: !project.worktrees.isEmpty
                )
            ]

            guard !collapsedProjectIDs.contains(project.id) else {
                return nodes
            }

            nodes.append(contentsOf: project.worktrees.map {
                WorkspaceNode(
                    selection: .worktree($0.id),
                    kind: .worktree,
                    parentProjectID: project.id,
                    title: $0.name,
                    branchName: $0.branch,
                    depth: 1,
                    hasChildren: false
                )
            })
            return nodes
        }
    }

    func project(for selection: WorkspaceSelection) -> Project? {
        switch selection {
        case let .project(projectID):
            return projects.first { $0.id == projectID }
        case let .worktree(worktreeID):
            return projects.first { project in
                project.worktrees.contains { $0.id == worktreeID }
            }
        }
    }

    func project(id: UUID) -> Project? {
        projects.first { $0.id == id }
    }

    func worktree(for selection: WorkspaceSelection) -> Worktree? {
        guard case let .worktree(worktreeID) = selection else {
            return nil
        }

        return worktree(id: worktreeID)
    }

    func worktree(id: UUID) -> Worktree? {
        projects
            .flatMap(\.worktrees)
            .first { $0.id == id }
    }

    func projectForWorktree(id: UUID) -> Project? {
        projects.first { project in
            project.worktrees.contains(where: { $0.id == id })
        }
    }

    func path(for selection: WorkspaceSelection) -> String? {
        project(for: selection)?.path(for: selection)
    }

    func node(for selection: WorkspaceSelection) -> WorkspaceNode? {
        orderedNodes.first { $0.selection == selection }
    }

    static func fromImportedProjects(_ projects: [Project]) -> ProjectsState {
        ProjectsState(
            projects: projects,
            configuredSections: [],
            collapsedProjectIDs: [],
            collapsedSectionIDs: [],
            selection: projects.first.map { .project($0.id) } ?? .project(UUID()),
            nextProjectCount: projects.count + 1,
            nextWorktreeCount: 1
        )
    }
}
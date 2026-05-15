import Foundation

enum CommandPaletteQuery {
    static func filteredCommands(
        commandBar: CommandBarState,
        projects: ProjectsState
    ) -> [CommandID] {
        guard case .commandList = commandBar.mode else {
            return []
        }

        let trimmedQuery = commandBar.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let commands = visibleCommandsForCurrentContext(commandBar: commandBar, projects: projects)

        guard !trimmedQuery.isEmpty else {
            return commands
        }

        let scored = commands.enumerated().compactMap { index, command -> (CommandID, Int, Int)? in
            let candidateStrings = [command.title] + command.keywords
            let bestScore = candidateStrings.compactMap {
                fuzzyScore(query: trimmedQuery, candidate: $0)
            }.min()
            guard let bestScore else {
                return nil
            }
            return (command, bestScore, index)
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.2 < rhs.2
                }
                return lhs.1 < rhs.1
            }
            .map(\.0)
    }

    static func filteredPickerItems(commandBar: CommandBarState) -> [CommandBarPickerItem] {
        guard case let .picker(_, items, _) = commandBar.mode else {
            return []
        }

        let trimmedQuery = commandBar.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return items
        }

        let scored = items.enumerated().compactMap { index, item -> (CommandBarPickerItem, Int, Int)? in
            let candidateStrings = [item.title, item.subtitle]
            let bestScore = candidateStrings.compactMap {
                fuzzyScore(query: trimmedQuery, candidate: $0)
            }.min()
            guard let bestScore else {
                return nil
            }
            return (item, bestScore, index)
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.2 < rhs.2
                }
                return lhs.1 < rhs.1
            }
            .map(\.0)
    }

    static func visibleCommandsForCurrentContext(
        commandBar: CommandBarState,
        projects: ProjectsState
    ) -> [CommandID] {
        CommandID.allCases.filter { command in
            switch command {
            case .addWorktree, .deleteWorktree:
                guard let projectID = resolveProjectContextID(
                    projects: projects,
                    preferred: commandBar.projectContextID
                ),
                let project = projects.project(id: projectID)
                else {
                    return false
                }
                return project.isGitRepository
            default:
                return true
            }
        }
    }

    static func resolveProjectContextID(
        projects: ProjectsState,
        preferred: UUID?
    ) -> UUID? {
        if let preferred, projects.project(id: preferred) != nil {
            return preferred
        }

        switch projects.selection {
        case let .project(projectID):
            if projects.project(id: projectID) != nil {
                return projectID
            }
        case let .worktree(worktreeID):
            if let project = projects.projectForWorktree(id: worktreeID) {
                return project.id
            }
        }

        return projects.projects.first?.id
    }

    static func fuzzyScore(query: String, candidate: String) -> Int? {
        let filteredQuery = query
            .lowercased()
            .filter { !$0.isWhitespace }
        let loweredCandidate = candidate.lowercased()
        var searchIndex = loweredCandidate.startIndex
        var totalDistance = 0

        for queryCharacter in filteredQuery {
            guard let matchIndex = loweredCandidate[searchIndex...].firstIndex(of: queryCharacter) else {
                return nil
            }

            totalDistance += loweredCandidate.distance(from: searchIndex, to: matchIndex)
            searchIndex = loweredCandidate.index(after: matchIndex)
        }

        return totalDistance
    }
}

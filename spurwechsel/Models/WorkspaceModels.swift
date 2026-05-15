import Foundation

struct Worktree: Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var branch: String
    var path: String
    var isPrimary: Bool

    init(
        id: UUID = UUID(),
        name: String,
        branch: String,
        path: String = "",
        isPrimary: Bool = false
    ) {
        self.id = id
        self.name = name
        self.branch = branch
        self.path = path
        self.isPrimary = isPrimary
    }
}

struct Project: Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var branch: String
    var path: String
    var sectionIDs: [String]
    var worktrees: [Worktree]
    var isGitRepository: Bool

    init(
        id: UUID = UUID(),
        name: String,
        branch: String,
        path: String = "",
        sectionIDs: [String] = [],
        worktrees: [Worktree] = [],
        isGitRepository: Bool = true
    ) {
        self.id = id
        self.name = name
        self.branch = branch
        self.path = path
        self.sectionIDs = sectionIDs
        self.worktrees = worktrees
        self.isGitRepository = isGitRepository
    }

    func contains(_ selection: WorkspaceSelection) -> Bool {
        switch selection {
        case let .project(projectID):
            return projectID == id
        case let .worktree(worktreeID):
            return worktrees.contains { $0.id == worktreeID }
        }
    }

    func path(for selection: WorkspaceSelection) -> String? {
        switch selection {
        case let .project(projectID):
            return projectID == id ? path : nil
        case let .worktree(worktreeID):
            return worktrees.first(where: { $0.id == worktreeID })?.path
        }
    }
}

enum WorkspaceSelection: Hashable {
    case project(UUID)
    case worktree(UUID)

    var stableID: String {
        switch self {
        case let .project(id):
            return "project-\(id.uuidString.lowercased())"
        case let .worktree(id):
            return "worktree-\(id.uuidString.lowercased())"
        }
    }
}

struct WorkspaceNode: Identifiable, Equatable, Hashable {
    enum Kind: String, Hashable {
        case project
        case worktree
    }

    let selection: WorkspaceSelection
    let kind: Kind
    let parentProjectID: UUID
    let title: String
    let branchName: String
    let depth: Int
    let hasChildren: Bool

    var id: String { selection.stableID }
    var isProject: Bool { kind == .project }
}

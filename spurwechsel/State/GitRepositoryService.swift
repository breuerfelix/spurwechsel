import Foundation
import libgit2
import os

struct GitWorktreeSnapshot: Equatable {
    var name: String
    var path: String
    var branch: String
    var isPrimary: Bool
}

struct GitRepositorySnapshot: Equatable {
    var repositoryRootPath: String
    var currentBranch: String
    var worktrees: [GitWorktreeSnapshot]
}

enum GitRepositoryServiceError: LocalizedError, Equatable {
    case notRepository(String)
    case invalidWorktreeName(String)
    case unsupportedRepositoryState(String)
    case destinationAlreadyExists(String)
    case worktreeNotFound(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case let .notRepository(path):
            return "Not a git repository: \(path)"
        case let .invalidWorktreeName(name):
            return "Invalid worktree name: \(name)"
        case let .unsupportedRepositoryState(message):
            return message
        case let .destinationAlreadyExists(path):
            return "Worktree destination already exists: \(path)"
        case let .worktreeNotFound(path):
            return "Worktree not found: \(path)"
        case let .commandFailed(message):
            return message
        }
    }
}

protocol GitRepositoryServicing {
    func repositorySnapshot(at path: URL) throws -> GitRepositorySnapshot
    func createWorktree(repositoryPath: URL, projectName: String, worktreeName: String) throws -> GitWorktreeSnapshot
    func deleteWorktree(repositoryPath: URL, worktreePath: URL) throws
    func validateWorktreeName(_ name: String) throws -> String
}

struct GitRepositoryService: GitRepositoryServicing {
    private static let logger = Logger(
        subsystem: "dev.breuer.spurwechsel",
        category: "GitRepositoryService"
    )

    private let fileManager: FileManager
    private let environment: [String: String]

    init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.fileManager = fileManager
        self.environment = environment
    }

    func repositorySnapshot(at path: URL) throws -> GitRepositorySnapshot {
        try withLibGit2 {
            let normalizedPath = normalizePath(path.path)
            Self.logger.debug("Loading repository snapshot at \(normalizedPath, privacy: .public)")

            let repository = try openRepository(at: path)
            defer { git_repository_free(repository) }

            let repositoryRootPath = try repositoryWorkdirPath(repository)
            let currentBranch = try branchName(for: repository)
            var worktrees = [
                GitWorktreeSnapshot(
                    name: URL(fileURLWithPath: repositoryRootPath).lastPathComponent,
                    path: repositoryRootPath,
                    branch: currentBranch,
                    isPrimary: true
                )
            ]

            worktrees.append(contentsOf: try linkedWorktrees(for: repository))
            Self.logger.debug("Repository snapshot loaded: root=\(repositoryRootPath, privacy: .public), branch=\(currentBranch, privacy: .public), worktrees=\(worktrees.count, privacy: .public)")

            return GitRepositorySnapshot(
                repositoryRootPath: repositoryRootPath,
                currentBranch: currentBranch,
                worktrees: worktrees
            )
        }
    }

    func createWorktree(repositoryPath: URL, projectName: String, worktreeName: String) throws -> GitWorktreeSnapshot {
        try withLibGit2 {
            let validatedName = try validateWorktreeName(worktreeName)
            let repository = try openRepository(at: repositoryPath)
            defer { git_repository_free(repository) }

            let currentBranch = try branchName(for: repository)
            guard currentBranch != "detached" else {
                throw GitRepositoryServiceError.unsupportedRepositoryState(
                    "Cannot create worktree while repository HEAD is detached."
                )
            }

            let destination = worktreePath(projectName: projectName, worktreeName: validatedName)
            let destinationPath = destination.path
            Self.logger.debug("Create worktree requested project=\(projectName, privacy: .public) name=\(validatedName, privacy: .public) destination=\(destinationPath, privacy: .public)")

            if fileManager.fileExists(atPath: destinationPath) {
                throw GitRepositoryServiceError.destinationAlreadyExists(destinationPath)
            }

            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            var headOID = git_oid()
            try check(
                git_reference_name_to_id(&headOID, repository, "HEAD"),
                operation: "Resolve HEAD",
                context: repositoryPath.path
            )

            var commitPointer: OpaquePointer?
            try check(
                git_commit_lookup(&commitPointer, repository, &headOID),
                operation: "Lookup HEAD commit",
                context: repositoryPath.path
            )
            defer { git_commit_free(commitPointer) }

            let resolvedBranchName = try resolveAvailableBranchName(
                requestedName: validatedName,
                repository: repository
            )

            var branchReference: OpaquePointer?
            try check(
                git_branch_create(&branchReference, repository, resolvedBranchName, commitPointer, 0),
                operation: "Create branch",
                context: resolvedBranchName
            )
            defer { git_reference_free(branchReference) }

            var addOptions = git_worktree_add_options()
            try check(
                git_worktree_add_options_init(&addOptions, UInt32(GIT_WORKTREE_ADD_OPTIONS_VERSION)),
                operation: "Init worktree add options",
                context: resolvedBranchName
            )
            addOptions.ref = branchReference

            var worktreePointer: OpaquePointer?
            do {
                try check(
                    git_worktree_add(&worktreePointer, repository, validatedName, destinationPath, &addOptions),
                    operation: "Add worktree",
                    context: destinationPath
                )
            } catch {
                _ = git_branch_delete(branchReference)
                throw error
            }
            defer { git_worktree_free(worktreePointer) }

            Self.logger.debug("Create worktree succeeded at \(destinationPath, privacy: .public)")
            return GitWorktreeSnapshot(
                name: validatedName,
                path: normalizePath(destinationPath),
                branch: resolvedBranchName,
                isPrimary: false
            )
        }
    }

    func deleteWorktree(repositoryPath: URL, worktreePath: URL) throws {
        try withLibGit2 {
            let repository = try openRepository(at: repositoryPath)
            defer { git_repository_free(repository) }

            let normalizedTargetPath = normalizePath(worktreePath.path)
            Self.logger.debug("Delete worktree requested path=\(normalizedTargetPath, privacy: .public)")

            let worktreeName = try lookupWorktreeName(for: normalizedTargetPath, repository: repository)
            var worktreePointer: OpaquePointer?
            try check(
                git_worktree_lookup(&worktreePointer, repository, worktreeName),
                operation: "Lookup worktree",
                context: worktreeName
            )
            defer { git_worktree_free(worktreePointer) }

            var pruneOptions = git_worktree_prune_options()
            try check(
                git_worktree_prune_options_init(&pruneOptions, UInt32(GIT_WORKTREE_PRUNE_OPTIONS_VERSION)),
                operation: "Init worktree prune options",
                context: worktreeName
            )
            pruneOptions.flags = UInt32(GIT_WORKTREE_PRUNE_VALID.rawValue | GIT_WORKTREE_PRUNE_WORKING_TREE.rawValue)

            try check(
                git_worktree_prune(worktreePointer, &pruneOptions),
                operation: "Delete worktree",
                context: worktreeName
            )

            if fileManager.fileExists(atPath: normalizedTargetPath) {
                try? fileManager.removeItem(atPath: normalizedTargetPath)
            }

            Self.logger.debug("Delete worktree succeeded for \(normalizedTargetPath, privacy: .public)")
        }
    }

    func validateWorktreeName(_ name: String) throws -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw GitRepositoryServiceError.invalidWorktreeName(name)
        }
        guard trimmedName != ".", trimmedName != ".." else {
            throw GitRepositoryServiceError.invalidWorktreeName(name)
        }
        guard trimmedName.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil else {
            throw GitRepositoryServiceError.invalidWorktreeName(name)
        }
        return trimmedName
    }

    private func linkedWorktrees(for repository: OpaquePointer?) throws -> [GitWorktreeSnapshot] {
        var names = git_strarray()
        try check(
            git_worktree_list(&names, repository),
            operation: "List worktrees",
            context: nil
        )
        defer { git_strarray_dispose(&names) }

        guard let rawNames = names.strings else {
            return []
        }

        var snapshots: [GitWorktreeSnapshot] = []
        for index in 0 ..< Int(names.count) {
            guard let rawName = rawNames[index] else {
                continue
            }
            let name = String(cString: rawName)

            var worktreePointer: OpaquePointer?
            try check(
                git_worktree_lookup(&worktreePointer, repository, name),
                operation: "Lookup worktree",
                context: name
            )
            defer { git_worktree_free(worktreePointer) }

            guard let rawPath = git_worktree_path(worktreePointer) else {
                continue
            }

            let branch = try branchName(for: repository, worktreeName: name)
            snapshots.append(
                GitWorktreeSnapshot(
                    name: name,
                    path: normalizePath(String(cString: rawPath)),
                    branch: branch,
                    isPrimary: false
                )
            )
        }

        return snapshots.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func openRepository(at path: URL) throws -> OpaquePointer? {
        let normalizedPath = normalizePath(path.path)
        var repository: OpaquePointer?

        let status = git_repository_open_ext(
            &repository,
            normalizedPath,
            UInt32(GIT_REPOSITORY_OPEN_NO_SEARCH.rawValue),
            nil
        )

        guard status == 0, repository != nil else {
            let message = lastGitErrorMessage(defaultMessage: "Repository not found at \(normalizedPath)")
            Self.logger.error("libgit2 repository open failed for \(normalizedPath, privacy: .public): \(message, privacy: .public)")
            print("Spurwechsel git open failed for \(normalizedPath): \(message)")
            throw GitRepositoryServiceError.notRepository(normalizedPath)
        }

        return repository
    }

    private func repositoryWorkdirPath(_ repository: OpaquePointer?) throws -> String {
        guard let rawPath = git_repository_workdir(repository) else {
            throw GitRepositoryServiceError.commandFailed("Repository has no working directory.")
        }
        return normalizePath(String(cString: rawPath))
    }

    private func branchName(for repository: OpaquePointer?, worktreeName: String? = nil) throws -> String {
        let isDetached: Int32
        if let worktreeName {
            isDetached = git_repository_head_detached_for_worktree(repository, worktreeName)
        } else {
            isDetached = git_repository_head_detached(repository)
        }

        if isDetached == 1 {
            return "detached"
        }

        var reference: OpaquePointer?
        let status: Int32
        if let worktreeName {
            status = git_repository_head_for_worktree(&reference, repository, worktreeName)
        } else {
            status = git_repository_head(&reference, repository)
        }
        try check(status, operation: "Read HEAD", context: worktreeName)
        defer { git_reference_free(reference) }

        guard let shorthand = git_reference_shorthand(reference) else {
            throw GitRepositoryServiceError.commandFailed("Failed to read branch name.")
        }

        return String(cString: shorthand)
    }

    private func lookupWorktreeName(for path: String, repository: OpaquePointer?) throws -> String {
        let snapshots = try linkedWorktrees(for: repository)
        guard let match = snapshots.first(where: { normalizePath($0.path) == path }) else {
            throw GitRepositoryServiceError.worktreeNotFound(path)
        }
        return match.name
    }

    private func resolveAvailableBranchName(requestedName: String, repository: OpaquePointer?) throws -> String {
        var candidate = requestedName
        var suffix = 0

        while try localBranchExists(named: candidate, repository: repository) {
            candidate = "\(requestedName)-\(suffix)"
            suffix += 1
        }

        return candidate
    }

    private func localBranchExists(named name: String, repository: OpaquePointer?) throws -> Bool {
        var reference: OpaquePointer?
        let status = git_branch_lookup(&reference, repository, name, GIT_BRANCH_LOCAL)
        defer { git_reference_free(reference) }

        if status == 0 {
            return true
        }
        if status == Int32(GIT_ENOTFOUND.rawValue) {
            return false
        }
        let message = lastGitErrorMessage(defaultMessage: "Lookup branch failed (\(name))")
        throw GitRepositoryServiceError.commandFailed(message)
    }

    private func worktreePath(projectName: String, worktreeName: String) -> URL {
        let projectSlug = slug(projectName)
        let rootURL: URL
        if let configuredRoot = environment["SPURWECHSEL_WORKTREES_ROOT"], !configuredRoot.isEmpty {
            rootURL = URL(fileURLWithPath: configuredRoot, isDirectory: true)
        } else {
            rootURL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent(".spurwechsel", isDirectory: true)
                .appendingPathComponent("worktrees", isDirectory: true)
        }

        return rootURL
            .appendingPathComponent(projectSlug, isDirectory: true)
            .appendingPathComponent(worktreeName, isDirectory: true)
    }

    private func slug(_ value: String) -> String {
        let lowered = value.lowercased()
        let scalars = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" {
                return Character(scalar)
            }
            if scalar == "_" || scalar == " " {
                return "-"
            }
            return "-"
        }

        let compacted = String(scalars)
            .replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return compacted.isEmpty ? "project" : compacted
    }

    private func normalizePath(_ path: String) -> String {
        URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }

    private func check(_ status: Int32, operation: String, context: String?) throws {
        guard status == 0 else {
            let suffix = context.map { " (\($0))" } ?? ""
            let message = lastGitErrorMessage(defaultMessage: "\(operation) failed\(suffix)")
            Self.logger.error("\(operation, privacy: .public) failed\(suffix, privacy: .public): \(message, privacy: .public)")
            print("Spurwechsel git operation failed: \(operation)\(suffix): \(message)")
            throw GitRepositoryServiceError.commandFailed(message)
        }
    }

    private func lastGitErrorMessage(defaultMessage: String) -> String {
        guard let errorPointer = git_error_last(),
              let rawMessage = errorPointer.pointee.message
        else {
            return defaultMessage
        }
        return String(cString: rawMessage)
    }

    private func withLibGit2<T>(_ body: () throws -> T) throws -> T {
        git_libgit2_init()
        defer { git_libgit2_shutdown() }
        return try body()
    }
}

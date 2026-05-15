# Workspace And Git

## Purpose
Workspace layer turns persisted project-folder records into live project tree.
Git repositories get linked worktree discovery; plain folders stay single-node projects.

Main files:

- `spurwechsel/State/ProjectConfigStore.swift`
- `spurwechsel/State/GitRepositoryService.swift`
- `spurwechsel/State/AppCoordinator+CoreFlows.swift`
- `spurwechsel/State/AppState.swift`

## Data Model
- `ProjectRecord`: persisted project folder in config
- `Project`: runtime project node in UI (`isGitRepository` marks Git capability)
- `Worktree`: runtime linked worktree node in UI (Git projects only)
- `WorkspaceSelection`: selected `project` or `worktree`

## Refresh Flow
`refreshProjectsFromConfig()` does real reload:

1. Iterate configured `ProjectRecord`s.
2. Try opening each path with `libgit2`.
3. If Git repo: read repo root, current branch, linked worktrees.
4. If not Git repo but valid directory: keep as plain project with no branch/worktrees.
5. Preserve stable IDs by normalized path when possible.
6. Replace `ProjectsState`.
7. Prune stale agents, terminals, VSCode runtimes, and surface tabs.

## Import Flow
`importProjects(from:)`:

1. normalize selected directory paths
2. skip duplicates and non-directories
3. append records to config
4. save config
5. refresh runtime project tree

## External Deep-Link Open Flow
Deep-link action: `spurwechsel://open-workspace?workspace_b64=...&project_b64=...`

1. Decode and validate absolute workspace + project paths.
2. Try resolving workspace by exact normalized path match:
   - project root path
   - linked worktree path
3. If unresolved, refresh config snapshot once and retry.
4. If still unresolved and project root is not configured, import project root record, refresh, retry.
5. Select resolved workspace and keep current main view behavior.
6. Reuse existing main window, bring app to foreground, and restore window if minimized.

Notes:
- config persists project roots only (Git and non-Git)
- linked worktrees are discovered for Git projects and never persisted as separate project records
- normal close-button quit behavior stays unchanged; warm deep links reuse scene routing and foreground existing main window

## Worktree Creation
`GitRepositoryService.createWorktree(...)`:

- validates worktree name with `^[A-Za-z0-9._-]+$`
- refuses detached HEAD repos
- creates new branch from current HEAD
- creates linked worktree via `libgit2`

Default worktree root:

- `~/.spurwechsel/worktrees/<project-slug>/<worktree-name>`

Override with:

- `SPURWECHSEL_WORKTREES_ROOT`

## Worktree Deletion
Deletion path uses command-bar confirmation, then:

- prune linked worktree with `libgit2`
- try removing working tree directory
- clean agent terminals, workspace terminal, VSCode runtime, and tabs for deleted workspace
- refresh project list from config

## Important Invariants
- repo root is primary project node
- non-Git project has `isGitRepository == false`, empty branch label, no worktrees
- linked worktrees never become separate persisted project records
- stable IDs come from normalized filesystem path, not display name
- stale runtime resources are pruned after every refresh

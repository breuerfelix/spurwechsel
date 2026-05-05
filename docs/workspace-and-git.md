# Workspace And Git

## Purpose
Workspace layer turns persisted repo records into live project tree with discovered worktrees.

Main files:

- `spurwechsel/State/ProjectConfigStore.swift`
- `spurwechsel/State/GitRepositoryService.swift`
- `spurwechsel/State/AppCoordinator+CoreFlows.swift`
- `spurwechsel/State/AppState.swift`

## Data Model
- `ProjectRecord`: persisted repo root in config
- `Project`: runtime repo node in UI
- `Worktree`: runtime linked worktree node in UI
- `WorkspaceSelection`: selected `project` or `worktree`

## Refresh Flow
`refreshProjectsFromConfig()` does real reload:

1. Iterate configured `ProjectRecord`s.
2. Open each repo with `libgit2`.
3. Read repo root, current branch, linked worktrees.
4. Preserve stable IDs by normalized path when possible.
5. Replace `ProjectsState`.
6. Prune stale agents, terminals, VSCode runtimes, and surface tabs.

## Import Flow
`importProjects(from:)`:

1. normalize selected directory paths
2. skip duplicates and non-directories
3. validate each path is git repo
4. append valid records to config
5. save config
6. refresh runtime project tree

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
- config persists project repo roots only
- linked worktrees are discovered, not persisted as separate project records
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
- linked worktrees never become separate persisted project records
- stable IDs come from normalized filesystem path, not display name
- stale runtime resources are pruned after every refresh

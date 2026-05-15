# Workspace And Git

## Purpose
Workspace layer turns persisted project-folder records into live project tree.
Git repositories get linked worktree discovery; plain folders stay single-node projects.

Main files:

- `spurwechsel/State/ProjectConfigStore.swift`
- `spurwechsel/State/GitRepositoryService.swift`
- `spurwechsel/Features/Workspace/WorkspaceFeature.swift`
- `spurwechsel/Features/Workspace/WorkspaceFeatureModels.swift`
- `spurwechsel/App/AppFeature.swift`

## Data Model
- `ProjectRecord`: persisted project folder in config
- `Project`: runtime project node in UI (`isGitRepository` marks Git capability)
- `Worktree`: runtime linked worktree node in UI (Git projects only)
- `WorkspaceSelection`: selected `project` or `worktree`

## Refresh Flow
Config refresh path:

1. Load config records.
2. Resolve each path with git service.
3. Git path: map repo root/branch/worktrees.
4. Non-git path: keep plain project node.
5. Preserve stable IDs by normalized path when possible.
6. Replace `ProjectsState`.
7. Prune stale agent/editor/workbench/runtime state.

## Import Flow
1. Normalize selected directory paths.
2. Skip duplicates and non-directories.
3. Append records to config.
4. Save config.
5. Refresh runtime project tree.

## External Deep-Link Open Flow
Deep-link action: `spurwechsel://open-workspace?workspace_b64=...&project_b64=...`

1. Decode and validate workspace/project paths.
2. Resolve selection by normalized path in current state.
3. If unresolved, refresh config snapshot and retry.
4. If still unresolved and project root missing, import project root and retry.
5. Select resolved workspace and keep current main-view behavior.
6. Bring existing app window to foreground.

## Worktree Creation
`GitRepositoryService.createWorktree(...)`:

- validates worktree name (`^[A-Za-z0-9._-]+$`)
- rejects detached HEAD
- creates branch from current HEAD
- creates linked worktree via `libgit2`

Default root:

- `~/.spurwechsel/worktrees/<project-slug>/<worktree-name>`

Override env:

- `SPURWECHSEL_WORKTREES_ROOT`

## Worktree Deletion
Deletion path:

- prune linked worktree via `libgit2`
- try removing worktree directory
- clean related agent terminals, workspace terminals, VSCode runtimes, and surface tabs
- refresh projects from config

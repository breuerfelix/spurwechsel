# Spurwechsel Layout And Navigation

## Window Anatomy
- top bar with window chrome handling, view switching, preview switching, command bar trigger
- optional left sidebar for agents
- main surface slot
- optional preview surface slot
- optional right sidebar for projects/worktrees

Entry points:
- `spurwechsel/Features/Shell/ShellRootView.swift`
- `spurwechsel/Features/Shell/ShellView.swift`

## Surface Model
Spurwechsel uses surface tabs plus mounted slots:

- `SurfaceTabID` describes content identity
- `SurfaceTabState` stores known tabs and selected tab
- `SurfaceMountState` maps content into `.main` and `.preview`

Types live in `spurwechsel/Features/Workbench/SurfaceModels.swift`.

## Supported Main Views
- `agent`
- `terminal`
- `vscode`

Preview cannot duplicate current main view.

## Shell Rules
- left sidebar auto-hides for `terminal` and `vscode` main views
- preview selection stored per main view in `previewConfigurations`
- preview mount clears if it would duplicate main surface
- focus memory tracked per main view with `preferredFocusedSlotByMainView`

## Default Navigation Behavior
- selecting workspace retargets current main surface to same feature for new workspace
- selecting agent session switches workspace selection with it
- opening preview auto-creates backing surface tab if needed
- closing preview keeps selected preview kind cached for later restore

## Ownership
Navigation and mount flow is now reducer-driven:

- root coordination: `spurwechsel/App/AppFeature.swift`
- shell state: `spurwechsel/Features/Shell/ShellFeature.swift`
- tab/mount behavior: `spurwechsel/Features/Workbench/WorkbenchFeature.swift`

## Main View Content
- `AgentMainView`: terminal-backed agent session or empty state
- `ProjectTerminalMainView`: shell for selected workspace
- `VSCodeMainView`: embedded `WKWebView` for running `code-server`

## Empty And Error States
- no workspace imported: onboarding state with project import hint
- preview kind cannot resolve: preview unavailable state
- agent/terminal/vscode runtime attach/start failures: explicit status state

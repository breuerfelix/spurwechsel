# Spurwechsel Layout And Navigation

## Window Anatomy
- top bar with window chrome handling, view switching, preview switching, command bar trigger
- optional left sidebar for agent lists
- main surface slot
- optional preview surface slot
- optional right sidebar for projects and worktrees

Entry point: `spurwechsel/ContentView.swift`.

## Surface Model
Spurwechsel does not hardcode one panel per feature. It uses surface tabs plus mounted slots:

- `SurfaceTabID` describes content identity
- `SurfaceTabState` stores known tabs and selected tab
- `SurfaceMountState` maps selected content into `.main` and `.preview`

Important types live in `spurwechsel/State/AppState.swift`.

## Supported Main Views
- `agent`
- `terminal`
- `vscode`

Main view and preview view share `SurfaceKind`. Preview cannot duplicate current main view.

## Shell Rules
- left sidebar auto-hides for `terminal` and `vscode` main views
- preview selection is stored per main view in `previewConfigurations`
- preview mount is cleared if it would duplicate selected main surface
- focus memory is tracked per main view with `preferredFocusedSlotByMainView`

## Default Navigation Behavior
- selecting workspace retargets current main surface to same feature for new workspace
- selecting agent session switches workspace selection with it
- opening preview auto-creates backing surface tab if needed
- closing preview keeps selected preview kind cached for later restore

## Key Flow Functions
- `initializeSurfaceTabs()`
- `selectSurfaceTab(_:)`
- `selectSurfaceForMainView(_:selection:)`
- `syncMountedSurfaces()`
- `requestSurfaceFocus(_:)`

All live in `spurwechsel/State/AppCoordinator+CoreFlows.swift`.

## Main View Content
- `AgentMainView`: terminal-backed agent session or empty state
- `ProjectTerminalMainView`: shell for selected workspace
- `VSCodeMainView`: embedded `WKWebView` for running `code-server`

## Preview Behavior
Preview is real second surface, not overlay. It can show:

- agent surface for current workspace
- workspace terminal
- VSCode web surface

If preview mounts VSCode, coordinator also ensures `code-server` is running for selected workspace.

## Empty And Error States
- if no workspace is imported, main surface shows onboarding state with project import hint
- if preview kind cannot resolve for selected workspace, preview surface shows unavailable state
- if agent/terminal/vscode runtime cannot attach, surface shows explicit status or failure state

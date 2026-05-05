# Spurwechsel App Architecture

## Top-Level Shape
App uses store-plus-coordinator setup.

- `spurwechsel/spurwechselApp.swift` boots app and termination coordinator
- `spurwechsel/ContentView.swift` renders shell
- `spurwechsel/State/SpurwechselStore.swift` builds root store graph
- `spurwechsel/State/AppCoordinator.swift` receives intents
- `spurwechsel/State/AppCoordinator+CoreFlows.swift` contains behavior

## Store Graph
`SpurwechselAppStore` owns focused child stores:

- `ShellStore`
- `WorkspaceStore`
- `AgentSessionsStore`
- `TerminalStore`
- `EditorStore`
- `CommandPaletteStore`
- `WorkbenchStore`

This splits UI publishing by domain while still exposing one app-level object to SwiftUI.

## Dependency Graph
`AppDependencies.live()` builds mutable runtime services:

- `ProjectConfigStore`
- `GitRepositoryService`
- `TerminalSessionRegistry`
- `VSCodeServerRuntime`
- import URL provider

## Intent Flow
1. UI sends `AppIntent`.
2. `AppCoordinator.handle(_:)` routes intent.
3. Core flow mutates store state and starts side effects.
4. Child stores publish changes back into SwiftUI.

External deep links use delegate path, then same coordinator core:
1. `NSApplicationDelegate.application(_:open:)` receives URL.
2. Delegate queues URLs during cold launch until store exists.
3. `AppCoordinator.handleExternalURL(_:)` decodes and routes to workspace import/select flow.

## State Domains
- shell/layout: theme, sidebars, preview, focus, shutdown, window activity
- workspace: imported repos, worktrees, selection, collapse state
- agents: configured agent sessions and selected session
- editor: per-workspace VSCode state and warm web runtimes
- terminal: workspace terminal attachment metadata
- workbench: surface tabs and mounted main/preview slots

## Key Invariants
- single main app window
- one selected workspace at time
- one selected main surface tab at time
- same surface ID cannot mount in both main and preview slots
- agent terminal controllers are reused by stable session IDs
- workspace terminal controllers are reused by stable workspace IDs
- config file is normalized before save

## Shutdown Model
Termination path lives in `AppTerminationCoordinator` plus `prepareForTermination()`.

- app asks terminal registry to close all sessions
- app asks `VSCodeServerRuntime` to stop
- grace timeout may escalate to force kill
- summary returns forced kill count and timeout count

## Best Entry Points For Changes
- navigation or layout: `ContentView.swift`, `AppState.swift`, `AppCoordinator+CoreFlows.swift`
- project/worktree logic: `ProjectConfigStore.swift`, `GitRepositoryService.swift`
- agent launch behavior: `AgentTerminalRuntime.swift`, `AppCoordinator+CoreFlows.swift`
- VSCode behavior: `VSCodeServerRuntime.swift`, `BrowserWebViewRuntime.swift`

# Spurwechsel App Architecture

## Top-Level Shape

App now uses TCA root store and feature reducers.

- `spurwechsel/spurwechselApp.swift` boots app, binds dependencies, owns app delegate bridge
- `spurwechsel/App/AppFeature.swift` is root reducer and cross-feature coordinator
- `spurwechsel/App/AppView.swift` + `spurwechsel/Features/Shell/ShellRootView.swift` render shell
- `spurwechsel/App/AppRuntime.swift` owns non-editor mutable runtime services (config store, UI state persistence, terminal registry)
- `spurwechsel/Features/Editor/EditorRuntime.swift` owns the VSCode process runtime and retained webview cache

## Feature Graph

`AppFeature.State` composes domain reducers:

- `ShellFeature`
- `WorkbenchFeature`
- `WorkspaceFeature`
- `AgentFeature`
- `EditorFeature`
- `CommandPaletteFeature`
- `LifecycleFeature`

## Dependency Graph

Runtime boundaries use dependency clients in `spurwechsel/Shared/Dependencies/DependencyClients.swift`:

- `ConfigClient`
- `GitClient`
- `ImportPanelClient`
- `TerminalRegistryClient`
- `VSCodeRuntimeClient`
- `AppControlClient` for direct app/window control such as quit and main-window activation

The VSCode dependency is editor-oriented: `EditorFeature` decides when to start, reuse, stop, and prune VSCode browser runtimes; `EditorRuntime` provides the imperative process and retained-webview implementation behind that boundary.
`VSCodeRuntimeClient.loadWorkspaceInBrowser` returns a structured browser-load result, so overlay readiness remains editor-owned and does not depend on shell view switching side effects.

## Action Flow

1. UI sends feature or app action into `StoreOf<AppFeature>`.
2. Child reducers mutate local state.
3. Root reducer handles cross-feature coordination and runtime side effects.
4. Runtime events (terminal/VSCode/webview) flow back as typed actions.

Editor-specific flow:

1. `AppFeature` forwards workspace-selection and visibility changes into `EditorFeature`.
2. `EditorFeature` owns editor session state and requests runtime work through `VSCodeRuntimeClient`.
3. `EditorRuntime` forwards `VSCodeServerRuntime` and retained webview events back as `.editor(...)` actions.

External deep links:

1. `NSApplicationDelegate.application(_:open:)` sends `.handleExternalURLs`.
2. `AppFeature` decodes and routes to workspace refresh/import/select path.
3. App window activation runs through dependency client callback.

## Key Invariants

- single main app window
- one selected workspace at time
- one selected main surface tab at time
- same surface ID never mounted in both main and preview
- terminal controllers reused by stable session/workspace IDs
- VSCode uses one shared `code-server` process; workspace switching reuses server and swaps cached browser view URL
- config load/save goes through `ConfigClient`

## Shutdown

Termination path is reducer-driven:

- `.prepareForTermination` starts shutdown state
- terminal and VSCode runtime shutdown run concurrently
- reducer stores summary (`forcedKillCount`, `timedOutCount`)

## Best Entry Points

- root coordination: `spurwechsel/App/AppFeature.swift`
- shell/layout behavior: `spurwechsel/Features/Shell/*`
- workspace + git: `spurwechsel/Features/Workspace/*`, `spurwechsel/State/GitRepositoryService.swift`
- agent runtime: `spurwechsel/Features/Agent/*`, `spurwechsel/State/AgentTerminalRuntime.swift`
- VSCode runtime: `spurwechsel/Features/Editor/*`, `spurwechsel/Features/Editor/EditorRuntime.swift`, `spurwechsel/State/VSCodeServerRuntime.swift`, `spurwechsel/State/BrowserWebViewRuntime.swift`

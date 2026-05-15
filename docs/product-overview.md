# Spurwechsel Product Overview

## What Spurwechsel Is
Spurwechsel is macOS workspace switchboard for repo-heavy, agent-heavy development. It keeps three live surfaces in one app:

- project and worktree navigation
- embedded terminal-backed agent sessions
- embedded `code-server` editor view

## What Exists Today
Important integrations:

- git repository and worktree discovery via `libgit2`
- plain folder projects with Git capability detection
- persistent config in `~/.spurwechsel/config.yaml`
- real terminal surfaces backed by Ghostty
- configurable agent launch commands
- embedded `code-server` process with `WKWebView`
- coordinated shutdown for terminals and `code-server`
- TCA-first app architecture (`StoreOf<AppFeature>`) with feature reducers

## Main User Flow
1. Load configured projects.
2. Resolve each path into Git project/worktrees or plain project.
3. Select project/worktree in right sidebar.
4. Open agent, terminal, or VSCode as main surface.
5. Optionally open second surface in preview pane.
6. Launch agent commands in selected workspace directory.

## Core Subsystems
- App/root reducer: `spurwechsel/App/AppFeature.swift`
- Shell/view composition: `spurwechsel/Features/Shell/*`
- Config loading/validation: `spurwechsel/State/ProjectConfigStore.swift`, `spurwechsel/State/ConfigResolver.swift`
- Git/worktrees: `spurwechsel/State/GitRepositoryService.swift`
- Agent runtime: `spurwechsel/Features/Agent/*`, `spurwechsel/State/AgentTerminalRuntime.swift`
- VSCode runtime: `spurwechsel/Features/Editor/*`, `spurwechsel/State/VSCodeServerRuntime.swift`, `spurwechsel/State/BrowserWebViewRuntime.swift`

## Best Starting Docs
- [Quick Links](./quick-links.md)
- [App Architecture](./app-architecture.md)
- [Workspace And Git](./workspace-and-git.md)
- [Agent Runtime](./agent-runtime.md)
- [VSCode Runtime](./vscode-runtime.md)

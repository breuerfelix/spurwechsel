# Spurwechsel Product Overview

## What Spurwechsel Is
Spurwechsel is macOS workspace switchboard for repo-heavy, agent-heavy development. It keeps three live surfaces in one app:

- project and worktree navigation
- embedded terminal-backed agent sessions
- embedded `code-server` for editor view

Goal: reduce context switches between repo selection, worktree management, agent launch, shell work, and editor work.

## What Exists Today
Current app is not prototype shell anymore. Important real integrations:

- git repository and worktree discovery via `libgit2`
- persistent project config in `~/.spurwechsel/config.yaml`
- real terminal surfaces backed by Ghostty
- configurable agent launch commands
- embedded `code-server` process with `WKWebView` host
- coordinated shutdown for terminals and `code-server`

## Main User Flow
1. Load persisted projects from config.
2. Resolve each configured repo into primary repo plus linked worktrees.
3. Select project or worktree in right sidebar.
4. Open agent, terminal, or VSCode as main surface.
5. Optionally keep second surface in preview pane.
6. Launch agent commands inside selected workspace directory.

## Core Subsystems
- Shell and view state: `spurwechsel/ContentView.swift`, `spurwechsel/State/AppState.swift`
- Store composition: `spurwechsel/State/SpurwechselStore.swift`
- Intent handling and orchestration: `spurwechsel/State/AppCoordinator.swift`, `spurwechsel/State/AppCoordinator+CoreFlows.swift`
- Config loading and validation: `spurwechsel/State/ProjectConfigStore.swift`, `spurwechsel/State/ConfigResolver.swift`
- Git + worktrees: `spurwechsel/State/GitRepositoryService.swift`
- Agent and terminal runtime: `spurwechsel/State/AgentTerminalRuntime.swift`
- VSCode runtime: `spurwechsel/State/VSCodeServerRuntime.swift`, `spurwechsel/State/BrowserWebViewRuntime.swift`

## Best Starting Docs
- [Quick Links](./quick-links.md)
- [App Architecture](./app-architecture.md)
- [Workspace And Git](./workspace-and-git.md)
- [Agent Runtime](./agent-runtime.md)
- [VSCode Runtime](./vscode-runtime.md)

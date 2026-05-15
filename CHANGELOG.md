# Changelog

All notable changes to this project will be documented in this file.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- New config setting `terminal.commandKeyMapsToControl` (default `false`) to optionally remap `Command+<key>` into `Control+<key>` while terminal or agent terminal surface is focused.
- Expanded built-in shortcut set with defaults for project selection, agent cycling/removal, split view toggle, and direct `agent` / `terminal` / `vscode` view switching.
- Managed `~/.spurwechsel/AGENTS.md` guide now lists default shortcut bindings explicitly, so agents can preserve or override built-ins correctly when editing config.
- OpenCode Warp rich-status mapping now matches Warp local-agent semantics, including `session_start -> running`, waiting states for approval/input events, and `idle_prompt` as a no-op.
- OpenCode agent sessions now read OpenCode config (`opencode.json`) to decide status mode: fallback sessions start `running`, Warp-plugin sessions start `idle` and transition with Warp events.
- Agent top bar now shows yellow warning badge for OpenCode sessions without Warp plugin rich-status setup, with hover-open popup instructions that stay open until click-dismissed, plus a popup action button that inserts agent-ready global install instructions into current agent.
- Added machine-local UI state file at `~/Library/Application Support/<bundle-id>/ui-state.json` for transient layout preferences that should persist across app restarts without touching `config.yaml`.

### Fixed
- Agent sessions now auto-remove when process exits or fails, matching `Remove Agent` cleanup so dead terminals do not stay visible.
- Left `Agents` sidebar now hides projects/worktrees without agents, still always shows current selected workspace, and uses a lighter selected-workspace background highlight while keeping selected agent row highlight.
- Left `Agents` sidebar removes subtle borders from non-selected agent rows and non-selected workspace group cards.
- Agent session names in sidebar/header now follow latest non-empty OSC terminal title events instead of sticking to generated names like `opencode-1`.
- Removed terminal runtime build warnings by resolving default terminal theme inside main-actor initializer.
- Left and right sidebars are now resizable with minimum widths and remember user-adjusted widths across app restarts.

## [0.5.0] - 2026-05-05

### Added
- focus spurwechsel when using the cli

### Fixed
- Tightened right `Projects` sidebar horizontal spacing so project rows align with left `Agents` sidebar content.
- Increased `Projects` sidebar worktree toggle hit area without adding visible button chrome, making hide/show worktrees easier to click.
- Locked left and right sidebars to fixed widths while resizing window, switched narrow-width auto-hide order to right sidebar, then preview, then left sidebar, and enforced a global minimum window size.
- Reduced fixed right sidebar width by about 15% to reclaim more space for main surface content.

## [0.4.0] - 2026-05-05

### Changed
- Updated bundled `libghostty-spm` package to latest upstream snapshot and kept Spurwechsel terminal lifecycle integration needed for managed session shutdown.
- Release archive pipeline now validates bundled CLI script presence and executable permissions before packaging and upload.
- Release builds now set app bundle `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` from tag version, avoiding static `1.0` bundle metadata across releases.
- Homebrew cask now disables `auto_updates` to ensure standard `brew upgrade` can move users to new tagged app payloads that include bundled CLI script updates.

## [0.3.0] - 2026-05-05

### Added
- New `remove-project` command with confirmation to remove current project from Spurwechsel config without deleting files on disk.
- App now supports external workspace open deep links: `spurwechsel://open-workspace?workspace_b64=...&project_b64=...`.
- Bundled CLI script at `Spurwechsel.app/Contents/Resources/spurwechsel-cli.sh` to open/import workspace from current terminal folder via deep link.

### Changed
- Default built-in agent config now marks `opencode` as default instead of `claude`.
- Removing project now closes and cleans project/worktree resources: agent sessions, workspace terminals, VSCode webviews, surface tabs, and cached editor session state.

### Fixed
- Adding folder that is not a git repository now shows command palette error notice instead of failing silently; mixed selections still import valid repos and report skipped non-repo folders.

## [0.2.0] - 2026-05-03

### Added
- MIT License

### Changed
- Close button now quits app; command palette adds `Quit`.
- Unified command and shortcut architecture: shortcuts now bind directly to command IDs via `shortcuts[].command`, and shortcut execution uses same command pipeline as command bar/menu flows.
- Command palette command rows now show configured keyboard shortcuts (for commands that have bindings), matching top bar shortcut style.
- App now auto-manages `AGENTS.md` beside `config.yaml`, with concise AI-agent instructions for supported config fields; file is rewritten when missing or stale.

### Fixed
- Embedded macOS terminal now preserves modifier keys for non-printing keys like `Shift+Enter`, improving multiline input behavior in agent CLIs.

## [0.1.0] - 2026-04-30

### Added
- Initial macOS release of Spurwechsel as workspace switchboard for repo-heavy, agent-heavy development.
- Unified shell with project and worktree navigation, main and preview surface slots, and switchable `agent`, `terminal`, and `vscode` views.
- Persistent YAML config for projects, agents, shortcuts, `code-server` port, and theme overrides, with validation and fallback diagnostics.
- Git repository import plus linked worktree discovery, creation, pruning, and deletion backed by `libgit2`.
- Real terminal-backed agent sessions with configurable launch commands, reusable terminal surfaces, status tracking, and coordinated cleanup.
- Embedded `code-server` workspace view in `WKWebView`, including startup detection, local URL resolution, warm webview caching, and explicit failure states.

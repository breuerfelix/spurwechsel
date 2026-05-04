# Changelog

All notable changes to this project will be documented in this file.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

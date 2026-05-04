# Spurwechsel Configuration

## Config File
Default path:

- `~/.spurwechsel/config.yaml`

Override path:

- `SPURWECHSEL_CONFIG_PATH`

Loader entry point: `spurwechsel/State/ProjectConfigStore.swift`.

## Managed Companion File
Spurwechsel manages a sibling `AGENTS.md` next to `config.yaml`.

- default: `~/.spurwechsel/AGENTS.md`
- with override: sibling of `SPURWECHSEL_CONFIG_PATH`

`AGENTS.md` contains concise instructions for AI agents on what they may configure in `config.yaml`.
File is app-owned and rewritten when missing or stale (for example after app updates or config saves).

## Config Domains
- `version`
- `codeServer`
- `projects`
- `agents`
- `shortcuts`
- `theme`

Raw file models live in `spurwechsel/Models/ConfigFileModels.swift`.
Resolved runtime models live in `spurwechsel/Models/ConfigModels.swift`.

## Resolution Pipeline
1. Read YAML.
2. Decode into `UserConfigFile`.
3. Normalize paths and explicit values.
4. Resolve defaults and validate each domain.
5. Return `ConfigLoadResult` with diagnostics.

Resolver lives in `spurwechsel/State/ConfigResolver.swift`.

## Project Records
Each project record stores:

- `path`
- optional `name`

Important detail: config stores repo roots only. Worktrees are discovered from git state, not persisted as separate records.

## Agent Records
Each agent record stores:

- `name`
- `command`
- optional `default`

If no valid agents remain after filtering, app falls back to built-ins:

- `opencode`
- `claude`
- `codex`

## Shortcut Records
Each shortcut stores:

- `command`
- `key`
- `modifiers`

`command` accepts any command ID from command registry (`toggle-command-bar`, `create-agent`, `open-vscode-view`, etc).

Resolver enforces one binding per command and removes signature collisions.

## Theme Records
Theme config may override any subset of light or dark palette tokens. Missing values inherit from defaults.

## Diagnostics
Invalid config does not crash app. It produces banner-visible diagnostics and continues with fallback values.

Common causes:

- bad YAML
- missing required project or agent fields
- invalid shortcut command or modifier
- invalid `codeServer.port`
- invalid theme token values

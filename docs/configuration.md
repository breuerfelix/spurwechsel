# Spurwechsel Configuration

## Config File
Default path:

- `~/.spurwechsel/config.yaml`

Override path:

- `SPURWECHSEL_CONFIG_PATH`

Loader entry point: `spurwechsel/State/ProjectConfigStore.swift`.

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

- `claude`
- `opencode`
- `codex`

## Shortcut Records
Each shortcut stores:

- `action`
- `key`
- `modifiers`

Supported actions today:

- `toggle-command-bar`
- `create-default-agent`

Resolver enforces one binding per action and removes signature collisions.

## Theme Records
Theme config may override any subset of light or dark palette tokens. Missing values inherit from defaults.

## Diagnostics
Invalid config does not crash app. It produces banner-visible diagnostics and continues with fallback values.

Common causes:

- bad YAML
- missing required project or agent fields
- invalid shortcut action or modifier
- invalid `codeServer.port`
- invalid theme token values

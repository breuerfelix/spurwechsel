# Agent Runtime

## Purpose
Agent sessions are real terminal-backed processes launched inside selected workspace.

Main files:

- `spurwechsel/State/AgentTerminalRuntime.swift`
- `spurwechsel/Features/Agent/AgentFeature.swift`
- `spurwechsel/Models/AgentModels.swift`
- `spurwechsel/Views/Agent/AgentMainView.swift`

## Session Model
`AgentSession` stores:

- workspace selection
- display name and raw terminal title
- detected agent kind
- launch command and launcher name
- working directory
- status + optional detail
- plugin metadata and exit code

Statuses:

- `launching`
- `idle`
- `running`
- `waitingApproval`
- `waitingInput`
- `exited`
- `failed`

Terminated sessions are removed through same cleanup path as manual remove.

## Rich Status Pipeline
OpenCode sessions can consume Warp plugin OSC 777 notifications.

Event mapping:

- `session_start` -> `running`
- `prompt_submit` -> `running`
- `permission_request` -> `waitingApproval`
- `question_asked` -> `waitingInput`
- `permission_replied` -> `running`
- `tool_complete` -> no status change
- `stop` -> `idle`
- `idle_prompt` -> no status change

Without plugin setup, fallback behavior stays `running` until process exit.

## Runtime Ownership
`TerminalSessionRegistry` owns reusable controllers by stable key:

- `.agent(UUID)` for agent sessions
- `.workspace(String)` for project terminals

This prevents process recreation on view remount.

## Launch Flow
1. Resolve selected workspace path.
2. Build `AgentSession` state.
3. Acquire terminal controller from registry.
4. Start configured command in login-shell launch plan.
5. Render controller in `AgentMainView`.

## Cleanup Paths
Agent resources are released when:

- user deletes session
- process exits/fails
- workspace disappears after refresh
- app terminates

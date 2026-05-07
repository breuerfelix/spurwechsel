# Agent Runtime

## Purpose
Agent sessions are real terminal-backed processes launched inside selected workspace.

Main files:

- `spurwechsel/State/AgentTerminalRuntime.swift`
- `spurwechsel/State/AppCoordinator+CoreFlows.swift`
- `spurwechsel/Models/AgentModels.swift`
- `spurwechsel/Views/Agent/AgentMainView.swift`

## Session Model
`AgentSession` stores:

- workspace selection
- display name
- launch command
- launcher name
- working directory
- terminal title
- status
- exit code

Statuses:

- `launching`
- `idle`
- `running`
- `waitingApproval`
- `waitingInput`
- `exited`
- `failed`

Terminated sessions are removed immediately using same cleanup path as manual `Remove Agent`, so `exited` and `failed` do not remain visible in session UI.

## Runtime Ownership
`TerminalSessionRegistry` owns reusable terminal controllers by stable key:

- `.agent(UUID)` for agent sessions
- `.workspace(String)` for project terminals

This prevents view remount from recreating process.

## Launch Flow
Agent launch happens from configured agent record:

1. resolve selected workspace path
2. create `AgentSession`
3. acquire terminal controller from registry
4. build login-shell launch plan for command
5. mount terminal in `AgentMainView`

Default agent comes from `SpurwechselConfig.resolvedDefaultAgent`.

## Terminal Implementation
`LocalShellTerminalSessionController` wraps Ghostty terminal surface.

Important behavior:

- keeps retained hosted surface for SwiftUI mounting
- updates title through callback
- emits exit once
- tracks active/inactive surface state for switch performance
- supports graceful shutdown then force kill fallback

## UI Behavior
`AgentMainView` shows:

- status rail with session and workspace info
- live terminal surface if controller exists
- state card if no session exists

## Cleanup Paths
Agent resources are released when:

- user deletes session
- agent process exits (success or failure)
- workspace disappears after refresh
- app terminates

Deletion also removes matching agent surface tabs.

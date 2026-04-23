# VSCode Runtime

## Purpose
VSCode view is embedded `code-server` process plus `WKWebView` host.

Main files:

- `spurwechsel/State/VSCodeServerRuntime.swift`
- `spurwechsel/State/BrowserWebViewRuntime.swift`
- `spurwechsel/State/AppCoordinator+CoreFlows.swift`
- `spurwechsel/Views/VSCode/VSCodeMainView.swift`
- `spurwechsel/Views/VSCode/EmbeddedWebViewHost.swift`

## Startup Flow
`ensureVSCodeServerForSelectedWorkspace(forceRestart:)`:

1. require selected workspace path
2. ensure per-workspace web runtime exists
3. reuse active server when possible
4. otherwise clear previous addresses and set status to `starting`
5. start `VSCodeServerRuntime` on configured port

## Process Launch
Runtime launches user shell with `-ilc` and executes:

- `code-server`
- `--auth none`
- `--disable-workspace-trust`
- `--disable-getting-started-override`
- `--user-data-dir ~/.vscode`
- `--extensions-dir ~/.vscode/extensions`
- `--bind-addr 127.0.0.1:<port>`

Port comes from config `codeServer.port`. Default: `8080`.

## Readiness Detection
Runtime parses stdout and stderr lines looking for local server URL. It also detects:

- auth prompts
- missing `code-server`
- port collisions
- startup failure before URL exists

## Browser Mount
After server URL exists, coordinator builds workspace URL:

- `http://127.0.0.1:<port>/?folder=<workspace-path>`

That URL loads into `EmbeddedWebViewRuntime`.

## Warm Runtime Cache
Coordinator keeps up to `6` `WKWebView` runtimes warm by workspace ID. Oldest gets evicted first.

## Failure States
`VSCodeServerStatus` includes:

- `missingWorkspace`
- `starting`
- `running`
- `authRequired`
- `stopping`
- `stopped`
- `cliMissing`
- `portInUse`
- `startupFailed`
- `urlNotFound`

`VSCodeMainView` maps those to status overlays until browser content is ready.

## Shutdown
Runtime supports graceful `terminate()`, then force kill, then timeout reporting. App shutdown waits for this summary.

# VSCode Runtime

## Purpose

VSCode view is embedded `code-server` process plus `WKWebView` host.

Main files:

- `spurwechsel/State/VSCodeServerRuntime.swift`
- `spurwechsel/State/BrowserWebViewRuntime.swift`
- `spurwechsel/Features/Editor/EditorRuntime.swift`
- `spurwechsel/Features/Editor/EditorFeature.swift`
- `spurwechsel/Features/Editor/VSCodeMainView.swift`
- `spurwechsel/Views/VSCode/EmbeddedWebViewHost.swift`

## Startup Flow

Reducer/runtime flow:

1. Require selected workspace path.
2. Set session status to `starting`.
3. `EditorFeature` starts shared `VSCodeServerRuntime` through `VSCodeRuntimeClient` on configured port if no active server exists.
4. `EditorRuntime` forwards runtime events (`starting`, `serverReady`, `failed`, `stopped`) back into `.editor(.runtimeEvent(...))`.
5. `EditorFeature` reuses running server across workspace switches and loads workspace URL into retained browser runtime.

## Process Launch

Runtime launches user shell with `-ilc` and executes `code-server` bound to `127.0.0.1:<port>`.

Port source: config `codeServer.port` (default `8080`).

## Browser Mount

Workspace URL format:

- `http://127.0.0.1:<port>/?folder=<workspace-path>`

That URL loads into `EmbeddedWebViewRuntime`.

## Warm Runtime Cache

`EditorRuntime` keeps up to `6` `WKWebView` runtimes warm by workspace ID. Oldest gets evicted first.

Inactive retained webviews must be hidden with `isHidden` while they are off-screen. The retained host does that in `EmbeddedWebViewHost`, which avoids black compositing artifacts during fast workspace switching.

`EditorRuntime` also forwards browser navigation events (`started`, `committed`, `finished`, `failed`) so overlay state follows actual page readiness instead of only process state.

Browser loads now return a structured runtime result (`startedNavigation`, `alreadyRequestedPage(isLoading:)`, `runtimeUnavailable`) so `EditorFeature` can decide overlay readiness from actual `WKWebView` load state even when no new navigation starts.

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

`VSCodeMainView` maps these to explicit status overlays until browser content is ready.

## Shutdown

Normal VSCode startup, reuse, browser loading, and workspace-scoped cache cleanup are editor-owned.

App termination still runs VSCode shutdown alongside terminal shutdown and records timeout/force-kill summary in app state.

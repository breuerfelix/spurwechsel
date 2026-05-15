import ComposableArchitecture
import Foundation
import GhosttyTerminal

@MainActor
struct AppComposition {
    let runtime: AppRuntime
    let editorRuntime: EditorRuntime
    let shellSceneBridge: ShellSceneBridge
    let windowEventRelay: WindowEventRelay
    let store: StoreOf<AppFeature>

    static func live(
        lifecycleBridge: AppLifecycleBridge
    ) -> AppComposition {
        let runtime = AppRuntime()
        let editorRuntime = EditorRuntime()
        let windowEventRelay = WindowEventRelay()
        let shellSceneBridge = makeShellSceneBridge(runtime: runtime, editorRuntime: editorRuntime)
        let store = makeStore(
            runtime: runtime,
            editorRuntime: editorRuntime,
            windowEventRelay: windowEventRelay,
            lifecycleBridge: lifecycleBridge
        )

        lifecycleBridge.connect(
            didFinishLaunching: {
                store.send(.lifecycle(.appDidFinishLaunching))
            },
            openURLs: { urls in
                store.send(.lifecycle(.openURLs(urls)))
            },
            requestTermination: { requestID in
                store.send(.lifecycle(.terminationRequested(requestID)))
            }
        )

        return AppComposition(
            runtime: runtime,
            editorRuntime: editorRuntime,
            shellSceneBridge: shellSceneBridge,
            windowEventRelay: windowEventRelay,
            store: store
        )
    }

    static func preview(
        runtime: AppRuntime,
        editorRuntime: EditorRuntime,
        store: StoreOf<AppFeature>
    ) -> AppComposition {
        let windowEventRelay = WindowEventRelay()
        return AppComposition(
            runtime: runtime,
            editorRuntime: editorRuntime,
            shellSceneBridge: makeShellSceneBridge(runtime: runtime, editorRuntime: editorRuntime),
            windowEventRelay: windowEventRelay,
            store: store
        )
    }

    private static func makeStore(
        runtime: AppRuntime,
        editorRuntime: EditorRuntime,
        windowEventRelay: WindowEventRelay,
        lifecycleBridge: AppLifecycleBridge
    ) -> StoreOf<AppFeature> {
        Store(
            initialState: AppBootstrap.makeInitialState(runtime: runtime),
            reducer: { AppFeature() },
            withDependencies: { dependencies in
                RuntimeDependencyAssembly.configure(
                    dependencies: &dependencies,
                    runtime: runtime,
                    editorRuntime: editorRuntime,
                    windowEventRelay: windowEventRelay,
                    lifecycleBridge: lifecycleBridge
                )
            }
        )
    }

    private static func makeShellSceneBridge(
        runtime: AppRuntime,
        editorRuntime: EditorRuntime
    ) -> ShellSceneBridge {
        ShellSceneBridge(
            agentTerminalController: { sessionID in
                runtime.agentTerminalController(for: sessionID)
            },
            workspaceTerminalController: { workspaceID, workingDirectory, terminalTheme in
                runtime.workspaceTerminalController(
                    workspaceID: workspaceID,
                    workingDirectory: workingDirectory,
                    terminalTheme: terminalTheme
                )
            },
            webRuntimeIfPrepared: { workspaceID in
                editorRuntime.webRuntimeIfPrepared(forWorkspaceID: workspaceID)
            }
        )
    }
}

@MainActor
private enum RuntimeDependencyAssembly {
    static func configure(
        dependencies: inout DependencyValues,
        runtime: AppRuntime,
        editorRuntime: EditorRuntime,
        windowEventRelay: WindowEventRelay,
        lifecycleBridge: AppLifecycleBridge
    ) {
        let configClient = ConfigClient(
            load: {
                runtime.configStore.loadResultEnsuringManagedFiles()
            },
            save: { fileConfig in
                try runtime.configStore.save(fileConfig)
            },
            configURL: {
                runtime.configStore.configURL
            },
            normalizeDirectoryPath: { url in
                runtime.configStore.normalizeDirectoryPath(url)
            },
            diagnosticsMessage: { diagnostics, configURL in
                ConfigClient.liveValue.diagnosticsMessage(diagnostics, configURL)
            }
        )
        dependencies.configClient = configClient

        let openCodeConfigClient = OpenCodeConfigClient(
            isWarpPluginInstalled: { workingDirectory in
                OpenCodeConfigProbe.live().isWarpPluginInstalled(workingDirectory: workingDirectory)
            }
        )
        dependencies.openCodeConfigClient = openCodeConfigClient

        dependencies.terminalRegistryClient = TerminalRegistryClient(
            agentController: { sessionID in
                runtime.agentTerminalController(for: sessionID)
            },
            workspaceController: { workspaceID, workingDirectory, terminalTheme in
                runtime.workspaceTerminalController(
                    workspaceID: workspaceID,
                    workingDirectory: workingDirectory,
                    terminalTheme: terminalTheme
                )
            },
            workspaceControllerIfLoaded: { workspaceID in
                runtime.workspaceTerminalControllerIfLoaded(workspaceID: workspaceID)
            },
            releaseAgentController: { sessionID in
                runtime.terminalRegistry.release(id: .agent(sessionID))
            },
            setAgentAttached: { sessionID, attached in
                runtime.terminalRegistry.setAttached(id: .agent(sessionID), attached: attached)
            },
            setWorkspaceAttached: { workspaceID, attached in
                runtime.terminalRegistry.setAttached(id: .workspace(workspaceID), attached: attached)
            },
            shutdownAll: { graceTimeout, forceKillTimeout in
                await runtime.terminalRegistry.shutdownAll(
                    graceTimeout: graceTimeout,
                    forceKillTimeout: forceKillTimeout
                )
            }
        )

        dependencies.agentRuntimeClient = AgentRuntimeClient(
            buildLaunchPlan: { agentName, command, workingDirectory, kind in
                let expectsRichStatus = kind == .opencode
                    ? openCodeConfigClient.isWarpPluginInstalled(workingDirectory)
                    : false
                let runtimeCommand = expectsRichStatus
                    ? "WARP_CLI_AGENT_PROTOCOL_VERSION=1 \(command)"
                    : command
                return AgentRuntimeLaunchPlan(
                    startupTitle: agentName,
                    runtimeCommand: runtimeCommand,
                    expectsRichStatus: expectsRichStatus
                )
            },
            start: { sessionID, workingDirectory, terminalTheme, launchPlan in
                AsyncStream { continuation in
                    _ = runtime.terminalRegistry.acquire(id: .agent(sessionID)) {
                        let controllerLaunchPlan = LocalShellTerminalSessionController.makeCommandLaunchPlan(
                            command: launchPlan.runtimeCommand,
                            workingDirectory: workingDirectory
                        )
                        return LocalShellTerminalSessionController(
                            sessionID: sessionID,
                            startupTitle: launchPlan.startupTitle,
                            launchPlan: controllerLaunchPlan,
                            terminalTheme: terminalTheme,
                            onTitleChange: { title in
                                continuation.yield(.terminalTitleChanged(title))
                            },
                            onProcessTerminated: { exitCode in
                                continuation.yield(.processTerminated(exitCode))
                                continuation.finish()
                            },
                            onDesktopNotification: { title, body in
                                continuation.yield(.desktopNotification(title: title, body: body))
                            }
                        )
                    }
                    continuation.yield(.controllerReady)

                    continuation.onTermination = { @Sendable _ in
                        Task { @MainActor in
                            runtime.terminalRegistry.release(id: .agent(sessionID))
                        }
                    }
                }
            }
        )

        dependencies.vscodeRuntimeClient = VSCodeRuntimeClient(
            start: { workspaceID, workspacePath, port in
                editorRuntime.startStream(
                    workspaceID: workspaceID,
                    workspacePath: workspacePath,
                    port: port
                )
            },
            browserEvents: {
                editorRuntime.browserEvents()
            },
            shutdown: { graceTimeout, forceKillTimeout in
                await editorRuntime.shutdown(
                    graceTimeout: graceTimeout,
                    forceKillTimeout: forceKillTimeout
                )
            },
            stop: {
                editorRuntime.stop()
            },
            prepareWebRuntime: { workspaceID in
                editorRuntime.prepareWebRuntime(forWorkspaceID: workspaceID)
            },
            webRuntimeIfPrepared: { workspaceID in
                editorRuntime.webRuntimeIfPrepared(forWorkspaceID: workspaceID)
            },
            loadWorkspaceInBrowser: { workspaceID, workspacePath, serverURL in
                editorRuntime.loadWorkspaceInBrowser(
                    workspaceID: workspaceID,
                    workspacePath: workspacePath,
                    serverURL: serverURL
                )
            },
            invalidateBrowserAddresses: {
                editorRuntime.invalidateBrowserAddresses()
            },
            syncBrowserRuntimeCache: { keepingWorkspaceIDs in
                editorRuntime.syncBrowserRuntimeCache(keepingWorkspaceIDs: keepingWorkspaceIDs)
            },
            removeBrowserRuntime: { workspaceID in
                editorRuntime.removeBrowserRuntime(forWorkspaceID: workspaceID)
            }
        )

        dependencies.layoutPersistenceClient = LayoutPersistenceClient(
            persistUIState: { layout, projects in
                runtime.persistUIState(
                    layout: layout,
                    projects: projects
                )
            }
        )

        dependencies.appControlClient = AppControlClient(
            activateMainWindowForExternalOpen: {
                runtime.activateMainWindowForExternalOpen()
            },
            requestApplicationQuit: {
                runtime.requestApplicationQuit()
            }
        )

        dependencies.appLifecycleBridgeClient = AppLifecycleBridgeClient(
            completeTerminationRequest: { requestID, shouldTerminate in
                lifecycleBridge.completeTerminationRequest(
                    requestID,
                    shouldTerminate: shouldTerminate
                )
            }
        )

        dependencies.windowClient = WindowClient(
            appActiveStream: {
                windowEventRelay.appActiveStream()
            },
            windowKeyStream: {
                windowEventRelay.windowKeyStream()
            },
            focusedSurfaceSlotStream: {
                windowEventRelay.focusedSurfaceSlotStream()
            },
            windowChromeStream: {
                windowEventRelay.windowChromeStream()
            },
            publishAppActive: { isActive in
                windowEventRelay.publishAppActive(isActive)
            },
            publishWindowKey: { isKey in
                windowEventRelay.publishWindowKey(isKey)
            },
            publishFocusedSurfaceSlot: { slot in
                windowEventRelay.publishFocusedSurfaceSlot(slot)
            },
            publishWindowChrome: { state in
                windowEventRelay.publishWindowChrome(state)
            }
        )
    }
}

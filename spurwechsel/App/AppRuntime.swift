import AppKit
import ComposableArchitecture
import Foundation
import GhosttyTerminal
import os

@MainActor
final class AppRuntime {
    static let shutdownGraceTimeout: TimeInterval = 2.0
    static let shutdownForceKillTimeout: TimeInterval = 1.5

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "dev.breuer.spurwechsel",
        category: "SpurwechselRuntime"
    )

    let configStore: ProjectConfigStore
    let uiStateStore: UIStateStore
    let terminalRegistry: TerminalSessionRegistry
    let voiceInputRuntime: VoiceInputRuntime
    private var importedGhosttyTerminalConfig: ImportedGhosttyTerminalConfig

    init(
        configStore: ProjectConfigStore,
        uiStateStore: UIStateStore,
        terminalRegistry: TerminalSessionRegistry,
        voiceInputRuntime: VoiceInputRuntime
    ) {
        self.configStore = configStore
        self.uiStateStore = uiStateStore
        self.terminalRegistry = terminalRegistry
        self.voiceInputRuntime = voiceInputRuntime
        importedGhosttyTerminalConfig = GhosttyUserConfigLoader().load()
    }

    convenience init() {
        self.init(
            configStore: ProjectConfigStore(),
            uiStateStore: UIStateStore(),
            terminalRegistry: TerminalSessionRegistry(),
            voiceInputRuntime: VoiceInputRuntime()
        )
    }

    func activateMainWindowForExternalOpen() {
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async {
            let candidateWindows = NSApp.windows.filter { !$0.isExcludedFromWindowsMenu }
            let targetWindow = NSApp.keyWindow ?? NSApp.mainWindow ?? candidateWindows.first
            guard let targetWindow else {
                Self.logger.error("External URL activation failed: no app window available.")
                return
            }

            if targetWindow.isMiniaturized {
                targetWindow.deminiaturize(nil)
            }

            targetWindow.makeKeyAndOrderFront(nil)
        }
    }

    func requestApplicationQuit() {
        Self.logger.debug("Quit requested via AppControlClient.")
        Self.logger.debug("Dispatching managed termination via AppLifecycleBridge.")
        _ = AppLifecycleBridge.shared.requestTerminationFromWindowClose()
    }

    func agentTerminalController(for sessionID: UUID) -> AgentTerminalSessionController? {
        terminalRegistry.controller(for: .agent(sessionID))
    }

    func currentImportedGhosttyTerminalConfig() -> ImportedGhosttyTerminalConfig {
        importedGhosttyTerminalConfig
    }

    func refreshImportedGhosttyTerminalConfig() {
        importedGhosttyTerminalConfig = GhosttyUserConfigLoader().load()
        terminalRegistry.setImportedGhosttyTerminalConfig(importedGhosttyTerminalConfig)
    }

    func workspaceTerminalController(
        workspaceSelection: WorkspaceSelection,
        projects: ProjectsState,
        terminalTheme: TerminalTheme
    ) -> LocalShellTerminalSessionController? {
        guard let workingDirectory = projects.path(for: workspaceSelection) else {
            return nil
        }

        return workspaceTerminalController(
            workspaceID: workspaceSelection.stableID,
            workingDirectory: workingDirectory,
            terminalTheme: terminalTheme
        )
    }

    func workspaceTerminalController(
        workspaceID: String,
        workingDirectory: String,
        terminalTheme: TerminalTheme
    ) -> LocalShellTerminalSessionController {
        terminalRegistry.acquire(id: .workspace(workspaceID)) {
            self.makeWorkspaceTerminalController(
                workingDirectory: workingDirectory,
                terminalTheme: terminalTheme
            )
        }
    }

    func workspaceTerminalControllerIfLoaded(
        workspaceID: String
    ) -> LocalShellTerminalSessionController? {
        terminalRegistry.controller(for: .workspace(workspaceID))
    }

    func persistUIState(
        layout: AppLayoutState,
        projects: ProjectsState
    ) {
        let state = UIStateFile(
            layout: UILayoutState(
                preferredLeftSidebarWidth: layout.preferredLeftSidebarWidth.map(Double.init),
                preferredRightSidebarWidth: layout.preferredRightSidebarWidth.map(Double.init),
                preferredPreviewWidth: layout.preferredPreviewWidth.map(Double.init),
                themeMode: layout.themeMode.rawValue
            ),
            workspace: UIWorkspaceState(
                collapsedProjectPaths: projects.collapsedProjectPaths.sorted(),
                collapsedSectionIDs: projects.collapsedSectionIDs.sorted()
            )
        )

        do {
            try uiStateStore.save(state)
        } catch {
            Self.logger.error("Failed to save UI state at \(self.uiStateStore.stateURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func makeWorkspaceTerminalController(
        workingDirectory: String,
        terminalTheme: TerminalTheme
    ) -> LocalShellTerminalSessionController {
        let launchPlan = LocalShellTerminalSessionController.makeDefaultShellLaunchPlan(
            workingDirectory: workingDirectory
        )
        return LocalShellTerminalSessionController(
            sessionID: UUID(),
            startupTitle: "terminal",
            launchPlan: launchPlan,
            terminalTheme: terminalTheme,
            importedGhosttyTerminalConfig: importedGhosttyTerminalConfig,
            onTitleChange: { _ in },
            onProcessTerminated: { _ in }
        )
    }
}

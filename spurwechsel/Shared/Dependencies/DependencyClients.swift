import AppKit
import ComposableArchitecture
import Foundation
import GhosttyTerminal

private enum DependencyClientError {
    static func unimplemented(_ name: String) -> Never {
        fatalError("Dependency \(name) not configured. Inject concrete value at app bootstrap.")
    }
}

struct AppControlClient {
    var activateMainWindowForExternalOpen: @MainActor @Sendable () -> Void
    var requestApplicationQuit: @MainActor @Sendable () -> Void
}

extension AppControlClient: DependencyKey {
    static let liveValue = AppControlClient(
        activateMainWindowForExternalOpen: {
            DependencyClientError.unimplemented("AppControlClient.activateMainWindowForExternalOpen")
        },
        requestApplicationQuit: {
            DependencyClientError.unimplemented("AppControlClient.requestApplicationQuit")
        }
    )
}

struct ConfigClient {
    var load: @MainActor @Sendable () async throws -> ConfigLoadResult
    var save: @MainActor @Sendable (_ fileConfig: UserConfigFile) async throws -> Void
    var configURL: @MainActor @Sendable () -> URL
    var normalizeDirectoryPath: @MainActor @Sendable (_ url: URL) -> String
    var diagnosticsMessage: @MainActor @Sendable (_ diagnostics: [ConfigDiagnostic], _ configURL: URL) -> ConfigNotificationState?
}

extension ConfigClient: DependencyKey {
    static let liveValue = ConfigClient(
        load: {
            ProjectConfigStore().loadResultEnsuringManagedFiles()
        },
        save: { fileConfig in
            try ProjectConfigStore().save(fileConfig)
        },
        configURL: {
            ProjectConfigStore.defaultConfigURL()
        },
        normalizeDirectoryPath: { url in
            ProjectConfigStore().normalizeDirectoryPath(url)
        },
        diagnosticsMessage: { diagnostics, configURL in
            guard !diagnostics.isEmpty else {
                return nil
            }
            let issueCount = diagnostics.count
            let firstIssue = diagnostics[0].message
            let detailSuffix = issueCount > 1 ? " \(issueCount - 1) more issue(s)." : ""
            let homeDirectory = NSHomeDirectory()
            let abbreviatedPath: String
            if configURL.path.hasPrefix(homeDirectory) {
                abbreviatedPath = configURL.path.replacingOccurrences(of: homeDirectory, with: "~")
            } else {
                abbreviatedPath = configURL.path
            }
            return ConfigNotificationState(
                title: "Config invalid",
                message: "Using defaults for invalid settings in \(abbreviatedPath).",
                detailMessage: firstIssue + detailSuffix
            )
        }
    )
}

struct GitClient {
    var repositorySnapshot: @MainActor @Sendable (_ path: URL) async throws -> GitRepositorySnapshot
    var createWorktree: @MainActor @Sendable (_ repositoryPath: URL, _ projectName: String, _ worktreeName: String) async throws -> GitWorktreeSnapshot
    var deleteWorktree: @MainActor @Sendable (_ repositoryPath: URL, _ worktreePath: URL) async throws -> Void
    var validateWorktreeName: @MainActor @Sendable (_ name: String) async throws -> String
}

extension GitClient: DependencyKey {
    static let liveValue = GitClient(
        repositorySnapshot: { path in
            try GitRepositoryService().repositorySnapshot(at: path)
        },
        createWorktree: { repositoryPath, projectName, worktreeName in
            try GitRepositoryService().createWorktree(
                repositoryPath: repositoryPath,
                projectName: projectName,
                worktreeName: worktreeName
            )
        },
        deleteWorktree: { repositoryPath, worktreePath in
            try GitRepositoryService().deleteWorktree(
                repositoryPath: repositoryPath,
                worktreePath: worktreePath
            )
        },
        validateWorktreeName: { name in
            try GitRepositoryService().validateWorktreeName(name)
        }
    )
}

struct ImportPanelClient {
    var selectProjectDirectories: @MainActor @Sendable () async -> [URL]?
}

extension ImportPanelClient: DependencyKey {
    static let liveValue = ImportPanelClient(
        selectProjectDirectories: {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = true
            panel.canCreateDirectories = false
            panel.prompt = "Add Project"
            panel.title = "Add New Project"
            return panel.runModal() == .OK ? panel.urls : nil
        }
    )
}

struct FileSystemClient {
    var directoryExists: @MainActor @Sendable (_ normalizedPath: String) -> Bool
}

extension FileSystemClient: DependencyKey {
    static let liveValue = FileSystemClient(
        directoryExists: { normalizedPath in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: normalizedPath, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
    )
}

struct LayoutPersistenceClient {
    var persistUIState: @MainActor @Sendable (_ layout: AppLayoutState, _ projects: ProjectsState) -> Void
}

extension LayoutPersistenceClient: DependencyKey {
    static let liveValue = LayoutPersistenceClient(
        persistUIState: { _, _ in
            DependencyClientError.unimplemented("LayoutPersistenceClient.persistUIState")
        }
    )
}

struct OpenCodeConfigClient {
    var isWarpPluginInstalled: @MainActor @Sendable (_ workingDirectory: String) -> Bool
}

extension OpenCodeConfigClient: DependencyKey {
    static let liveValue = OpenCodeConfigClient(
        isWarpPluginInstalled: { workingDirectory in
            OpenCodeConfigProbe.live().isWarpPluginInstalled(workingDirectory: workingDirectory)
        }
    )
}

struct AgentRuntimeLaunchPlan: Equatable {
    var startupTitle: String
    var runtimeCommand: String
    var expectsRichStatus: Bool
}

enum AgentRuntimeEvent: Equatable {
    case controllerReady
    case terminalTitleChanged(String)
    case processTerminated(Int32?)
    case desktopNotification(title: String, body: String)
}

struct TerminalRegistryClient {
    var agentController: @MainActor @Sendable (_ sessionID: UUID) -> AgentTerminalSessionController?
    var workspaceController: @MainActor @Sendable (
        _ workspaceID: String,
        _ workingDirectory: String,
        _ terminalTheme: TerminalTheme
    ) -> LocalShellTerminalSessionController
    var workspaceControllerIfLoaded: @MainActor @Sendable (_ workspaceID: String) -> LocalShellTerminalSessionController?
    var releaseAgentController: @MainActor @Sendable (_ sessionID: UUID) -> Void
    var setAgentAttached: @MainActor @Sendable (_ sessionID: UUID, _ attached: Bool) -> Void
    var setWorkspaceAttached: @MainActor @Sendable (_ workspaceID: String, _ attached: Bool) -> Void
    var shutdownAll: @MainActor @Sendable (_ graceTimeout: TimeInterval, _ forceKillTimeout: TimeInterval) async -> TerminalRegistryShutdownSummary
}

extension TerminalRegistryClient: DependencyKey {
    static let liveValue = TerminalRegistryClient(
        agentController: { _ in
            DependencyClientError.unimplemented("TerminalRegistryClient.agentController")
        },
        workspaceController: { _, _, _ in
            DependencyClientError.unimplemented("TerminalRegistryClient.workspaceController")
        },
        workspaceControllerIfLoaded: { _ in
            DependencyClientError.unimplemented("TerminalRegistryClient.workspaceControllerIfLoaded")
        },
        releaseAgentController: { _ in
            DependencyClientError.unimplemented("TerminalRegistryClient.releaseAgentController")
        },
        setAgentAttached: { _, _ in
            DependencyClientError.unimplemented("TerminalRegistryClient.setAgentAttached")
        },
        setWorkspaceAttached: { _, _ in
            DependencyClientError.unimplemented("TerminalRegistryClient.setWorkspaceAttached")
        },
        shutdownAll: { _, _ in
            DependencyClientError.unimplemented("TerminalRegistryClient.shutdownAll")
        }
    )
}

struct AgentRuntimeClient {
    var buildLaunchPlan: @MainActor @Sendable (
        _ agentName: String,
        _ command: String,
        _ workingDirectory: String,
        _ kind: AgentKind
    ) -> AgentRuntimeLaunchPlan
    var start: @MainActor @Sendable (
        _ sessionID: UUID,
        _ workingDirectory: String,
        _ terminalTheme: TerminalTheme,
        _ launchPlan: AgentRuntimeLaunchPlan
    ) -> AsyncStream<AgentRuntimeEvent>
}

extension AgentRuntimeClient: DependencyKey {
    static let liveValue = AgentRuntimeClient(
        buildLaunchPlan: { _, _, _, _ in
            DependencyClientError.unimplemented("AgentRuntimeClient.buildLaunchPlan")
        },
        start: { _, _, _, _ in
            DependencyClientError.unimplemented("AgentRuntimeClient.start")
        }
    )
}

struct VSCodeRuntimeClient {
    var start: @MainActor @Sendable (_ workspaceID: String, _ workspacePath: String, _ port: Int) -> AsyncThrowingStream<VSCodeServerRuntime.Event, Error>
    var browserEvents: @MainActor @Sendable () -> AsyncStream<EditorRuntime.BrowserEvent>
    var shutdown: @MainActor @Sendable (_ graceTimeout: TimeInterval, _ forceKillTimeout: TimeInterval) async -> VSCodeServerShutdownSummary
    var stop: @MainActor @Sendable () -> Void
    var prepareWebRuntime: @MainActor @Sendable (_ workspaceID: String) -> Void
    var webRuntimeIfPrepared: @MainActor @Sendable (_ workspaceID: String) -> EmbeddedWebViewRuntime?
    var loadWorkspaceInBrowser: @MainActor @Sendable (_ workspaceID: String, _ workspacePath: String, _ serverURL: URL) -> EditorRuntime.BrowserLoadResult
    var invalidateBrowserAddresses: @MainActor @Sendable () -> Void
    var syncBrowserRuntimeCache: @MainActor @Sendable (_ keepingWorkspaceIDs: Set<String>) -> Void
    var removeBrowserRuntime: @MainActor @Sendable (_ workspaceID: String) -> Void
}

extension VSCodeRuntimeClient: DependencyKey {
    static let liveValue = VSCodeRuntimeClient(
        start: { _, _, _ in
            DependencyClientError.unimplemented("VSCodeRuntimeClient.start")
        },
        browserEvents: {
            DependencyClientError.unimplemented("VSCodeRuntimeClient.browserEvents")
        },
        shutdown: { _, _ in
            DependencyClientError.unimplemented("VSCodeRuntimeClient.shutdown")
        },
        stop: {
            DependencyClientError.unimplemented("VSCodeRuntimeClient.stop")
        },
        prepareWebRuntime: { _ in
            DependencyClientError.unimplemented("VSCodeRuntimeClient.prepareWebRuntime")
        },
        webRuntimeIfPrepared: { _ in
            DependencyClientError.unimplemented("VSCodeRuntimeClient.webRuntimeIfPrepared")
        },
        loadWorkspaceInBrowser: { _, _, _ in
            DependencyClientError.unimplemented("VSCodeRuntimeClient.loadWorkspaceInBrowser")
        },
        invalidateBrowserAddresses: {
            DependencyClientError.unimplemented("VSCodeRuntimeClient.invalidateBrowserAddresses")
        },
        syncBrowserRuntimeCache: { _ in
            DependencyClientError.unimplemented("VSCodeRuntimeClient.syncBrowserRuntimeCache")
        },
        removeBrowserRuntime: { _ in
            DependencyClientError.unimplemented("VSCodeRuntimeClient.removeBrowserRuntime")
        }
    )
}

struct AppLifecycleBridgeClient {
    var completeTerminationRequest: @MainActor @Sendable (_ requestID: UUID, _ shouldTerminate: Bool) -> Void
}

extension AppLifecycleBridgeClient: DependencyKey {
    static let liveValue = AppLifecycleBridgeClient(
        completeTerminationRequest: { _, _ in
            DependencyClientError.unimplemented("AppLifecycleBridgeClient.completeTerminationRequest")
        }
    )
}

struct WindowClient {
    var appActiveStream: @MainActor @Sendable () -> AsyncStream<Bool>
    var windowKeyStream: @MainActor @Sendable () -> AsyncStream<Bool>
    var focusedSurfaceSlotStream: @MainActor @Sendable () -> AsyncStream<SurfaceSlot>
    var windowChromeStream: @MainActor @Sendable () -> AsyncStream<WindowChromeState>
    var publishAppActive: @MainActor @Sendable (_ isActive: Bool) -> Void
    var publishWindowKey: @MainActor @Sendable (_ isKey: Bool) -> Void
    var publishFocusedSurfaceSlot: @MainActor @Sendable (_ slot: SurfaceSlot) -> Void
    var publishWindowChrome: @MainActor @Sendable (_ state: WindowChromeState) -> Void
}

extension WindowClient {
    static let noop = WindowClient(
        appActiveStream: { AsyncStream { _ in } },
        windowKeyStream: { AsyncStream { _ in } },
        focusedSurfaceSlotStream: { AsyncStream { _ in } },
        windowChromeStream: { AsyncStream { _ in } },
        publishAppActive: { _ in },
        publishWindowKey: { _ in },
        publishFocusedSurfaceSlot: { _ in },
        publishWindowChrome: { _ in }
    )
}

extension WindowClient: DependencyKey {
    static let liveValue = WindowClient.noop
}

extension DependencyValues {
    var appControlClient: AppControlClient {
        get { self[AppControlClient.self] }
        set { self[AppControlClient.self] = newValue }
    }

    var configClient: ConfigClient {
        get { self[ConfigClient.self] }
        set { self[ConfigClient.self] = newValue }
    }

    var gitClient: GitClient {
        get { self[GitClient.self] }
        set { self[GitClient.self] = newValue }
    }

    var importPanelClient: ImportPanelClient {
        get { self[ImportPanelClient.self] }
        set { self[ImportPanelClient.self] = newValue }
    }

    var fileSystemClient: FileSystemClient {
        get { self[FileSystemClient.self] }
        set { self[FileSystemClient.self] = newValue }
    }

    var layoutPersistenceClient: LayoutPersistenceClient {
        get { self[LayoutPersistenceClient.self] }
        set { self[LayoutPersistenceClient.self] = newValue }
    }

    var openCodeConfigClient: OpenCodeConfigClient {
        get { self[OpenCodeConfigClient.self] }
        set { self[OpenCodeConfigClient.self] = newValue }
    }

    var terminalRegistryClient: TerminalRegistryClient {
        get { self[TerminalRegistryClient.self] }
        set { self[TerminalRegistryClient.self] = newValue }
    }

    var agentRuntimeClient: AgentRuntimeClient {
        get { self[AgentRuntimeClient.self] }
        set { self[AgentRuntimeClient.self] = newValue }
    }

    var vscodeRuntimeClient: VSCodeRuntimeClient {
        get { self[VSCodeRuntimeClient.self] }
        set { self[VSCodeRuntimeClient.self] = newValue }
    }

    var appLifecycleBridgeClient: AppLifecycleBridgeClient {
        get { self[AppLifecycleBridgeClient.self] }
        set { self[AppLifecycleBridgeClient.self] = newValue }
    }

    var windowClient: WindowClient {
        get { self[WindowClient.self] }
        set { self[WindowClient.self] = newValue }
    }
}

struct OpenCodeConfigProbe {
    var fileExists: @Sendable (String) -> Bool
    var readData: @Sendable (String) throws -> Data
    var homeDirectoryPath: @Sendable () -> String

    func isWarpPluginInstalled(workingDirectory: String) -> Bool {
        let localConfigPath = URL(fileURLWithPath: workingDirectory)
            .appendingPathComponent("opencode.json", isDirectory: false)
            .path
        if fileExists(localConfigPath) {
            return configContainsWarpPlugin(atPath: localConfigPath)
        }

        let globalConfigPath = URL(fileURLWithPath: homeDirectoryPath())
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("opencode", isDirectory: true)
            .appendingPathComponent("opencode.json", isDirectory: false)
            .path

        if fileExists(globalConfigPath) {
            return configContainsWarpPlugin(atPath: globalConfigPath)
        }

        return false
    }

    func configContainsWarpPlugin(atPath path: String) -> Bool {
        guard let data = try? readData(path),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let plugins = payload["plugin"] as? [Any]
        else {
            return false
        }

        return plugins.contains { plugin in
            if let pluginName = plugin as? String {
                return pluginName == "warp" || pluginName == "@warp-dot-dev/opencode-warp"
            }
            if let pluginRecord = plugin as? [String: Any],
               let pluginName = pluginRecord["name"] as? String {
                return pluginName == "warp" || pluginName == "@warp-dot-dev/opencode-warp"
            }
            return false
        }
    }
}

extension OpenCodeConfigProbe {
    static func live() -> OpenCodeConfigProbe {
        OpenCodeConfigProbe(
            fileExists: { path in
                FileManager.default.fileExists(atPath: path)
            },
            readData: { path in
                try Data(contentsOf: URL(fileURLWithPath: path))
            },
            homeDirectoryPath: {
                NSHomeDirectory()
            }
        )
    }
}

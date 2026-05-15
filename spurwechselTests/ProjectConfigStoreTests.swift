import ComposableArchitecture
import XCTest
import Yams
@testable import spurwechsel

final class ProjectConfigStoreTests: XCTestCase {

    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("spurwechsel-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
    }

    func testConfigRoundTripPersistsVersionAndProjects() throws {
        let configURL = temporaryDirectoryURL.appendingPathComponent("config.yaml")
        let configStore = ProjectConfigStore(configURL: configURL)
        let initialConfig = SpurwechselConfig(
            version: SpurwechselConfig.currentVersion,
            projects: [
                ProjectRecord(path: temporaryDirectoryURL.appendingPathComponent("alpha").path, name: "Alpha"),
                ProjectRecord(path: temporaryDirectoryURL.appendingPathComponent("beta").path, name: "Beta")
            ]
        )

        try configStore.save(UserConfigFile.explicit(from: initialConfig))
        let loadedConfig = try configStore.load()

        XCTAssertEqual(loadedConfig.version, SpurwechselConfig.currentVersion)
        XCTAssertEqual(loadedConfig.codeServer.resolvedPort, CodeServerConfig.defaultPort)
        XCTAssertEqual(loadedConfig.projects, initialConfig.projects)
        XCTAssertEqual(loadedConfig.agents, initialConfig.agents)
        XCTAssertEqual(
            shortcutsByCommand(loadedConfig.shortcuts),
            shortcutsByCommand(initialConfig.shortcuts)
        )
        XCTAssertEqual(loadedConfig.terminal, initialConfig.terminal)
        XCTAssertEqual(loadedConfig.resolvedAgents.map(\.displayName), ["opencode", "claude", "codex"])
        XCTAssertEqual(loadedConfig.resolvedDefaultAgent.displayName, "opencode")
        XCTAssertEqual(loadedConfig.resolvedShortcuts.count, SpurwechselConfig.defaultShortcuts.count)
        XCTAssertEqual(
            loadedConfig.resolvedShortcuts.first?.command,
            .toggleCommandBar
        )
        XCTAssertEqual(loadedConfig.theme, initialConfig.theme)
    }

    func testLoadResultEnsuringManagedFilesBootstrapsConfigAndAgentsGuide() throws {
        let configDirectoryURL = temporaryDirectoryURL.appendingPathComponent(".spurwechsel", isDirectory: true)
        let configURL = configDirectoryURL.appendingPathComponent("config.yaml")
        let configStore = ProjectConfigStore(configURL: configURL)

        let loadResult = configStore.loadResultEnsuringManagedFiles()

        XCTAssertFalse(loadResult.hasIssues)
        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path))

        let agentsURL = configDirectoryURL.appendingPathComponent("AGENTS.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: agentsURL.path))

        let configContents = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertTrue(configContents.contains("version: \(SpurwechselConfig.currentVersion)"))
        XCTAssertTrue(configContents.contains("codeServer:"))

        let agentsContents = try String(contentsOf: agentsURL, encoding: .utf8)
        XCTAssertTrue(agentsContents.contains("# Spurwechsel Agent Config Guide"))
        XCTAssertTrue(agentsContents.contains("This file is managed by Spurwechsel."))
        XCTAssertTrue(agentsContents.contains("## Default shortcut bindings"))
        XCTAssertTrue(agentsContents.contains("`⌘P`: `select-project`"))
        XCTAssertTrue(agentsContents.contains("## Supported shortcut command IDs"))
    }

    func testLoadResultEnsuringManagedFilesOverwritesStaleAgentsGuide() throws {
        let configDirectoryURL = temporaryDirectoryURL.appendingPathComponent(".spurwechsel", isDirectory: true)
        let configURL = configDirectoryURL.appendingPathComponent("config.yaml")
        let agentsURL = configDirectoryURL.appendingPathComponent("AGENTS.md")
        let configStore = ProjectConfigStore(configURL: configURL)

        try FileManager.default.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
        try "version: 1\n".write(to: configURL, atomically: true, encoding: .utf8)
        try "user custom text".write(to: agentsURL, atomically: true, encoding: .utf8)

        _ = configStore.loadResultEnsuringManagedFiles()

        let agentsContents = try String(contentsOf: agentsURL, encoding: .utf8)
        XCTAssertFalse(agentsContents.contains("user custom text"))
        XCTAssertTrue(agentsContents.contains("# Spurwechsel Agent Config Guide"))
    }

    func testConfigSaveOverwritesStaleAgentsGuide() throws {
        let configDirectoryURL = temporaryDirectoryURL.appendingPathComponent(".spurwechsel", isDirectory: true)
        let configURL = configDirectoryURL.appendingPathComponent("config.yaml")
        let agentsURL = configDirectoryURL.appendingPathComponent("AGENTS.md")
        let configStore = ProjectConfigStore(configURL: configURL)

        try FileManager.default.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
        try "stale".write(to: agentsURL, atomically: true, encoding: .utf8)

        try configStore.save(UserConfigFile.explicit(from: SpurwechselConfig()))

        let agentsContents = try String(contentsOf: agentsURL, encoding: .utf8)
        XCTAssertFalse(agentsContents.contains("stale"))
        XCTAssertTrue(agentsContents.contains("## Example"))
    }

    func testLoadResultWithoutThemeSectionUsesBuiltInDefaults() throws {
        let configURL = temporaryDirectoryURL.appendingPathComponent("config.yaml")
        let configStore = ProjectConfigStore(configURL: configURL)
        let yaml = """
        version: 1
        projects: []
        agents: []
        shortcuts: []
        """
        try yaml.appending("\n").write(to: configURL, atomically: true, encoding: .utf8)

        let loadResult = configStore.loadResult()

        XCTAssertEqual(loadResult.config.theme, SpurwechselConfig.defaultTheme)
    }

    func testLoadResultWithPartialThemeOverrideMergesWithDefaults() throws {
        let configURL = temporaryDirectoryURL.appendingPathComponent("config.yaml")
        let configStore = ProjectConfigStore(configURL: configURL)
        let yaml = """
        version: 1
        theme:
          light:
            accent: "#1234AB"
        """
        try yaml.appending("\n").write(to: configURL, atomically: true, encoding: .utf8)

        let loadResult = configStore.loadResult()

        XCTAssertEqual(loadResult.config.theme.light[.accent].hex, "#1234AB")
        XCTAssertEqual(
            loadResult.config.theme.light[.foreground].hex,
            SpurwechselConfig.defaultTheme.light[.foreground].hex
        )
        XCTAssertEqual(
            loadResult.config.theme.dark[.accent].hex,
            SpurwechselConfig.defaultTheme.dark[.accent].hex
        )
    }

    func testLoadResultWithUnknownThemeTokenReportsDiagnosticAndFallsBack() throws {
        let configURL = temporaryDirectoryURL.appendingPathComponent("config.yaml")
        let configStore = ProjectConfigStore(configURL: configURL)
        let yaml = """
        version: 1
        theme:
          dark:
            accentNope: "#112233"
        """
        try yaml.appending("\n").write(to: configURL, atomically: true, encoding: .utf8)

        let loadResult = configStore.loadResult()

        XCTAssertEqual(
            loadResult.config.theme.dark[.accent].hex,
            SpurwechselConfig.defaultTheme.dark[.accent].hex
        )
        XCTAssertTrue(loadResult.diagnostics.contains {
            $0.message.contains("theme.dark.accentNope is unsupported")
        })
    }

    func testLoadResultWithInvalidThemeHexReportsDiagnosticAndFallsBack() throws {
        let configURL = temporaryDirectoryURL.appendingPathComponent("config.yaml")
        let configStore = ProjectConfigStore(configURL: configURL)
        let yaml = """
        version: 1
        theme:
          dark:
            accent: "blue"
        """
        try yaml.appending("\n").write(to: configURL, atomically: true, encoding: .utf8)

        let loadResult = configStore.loadResult()

        XCTAssertEqual(
            loadResult.config.theme.dark[.accent].hex,
            SpurwechselConfig.defaultTheme.dark[.accent].hex
        )
        XCTAssertTrue(loadResult.diagnostics.contains {
            $0.message.contains("theme.dark.accent must be #RRGGBB or #RRGGBBAA")
        })
    }

    func testConfigSaveWritesExplicitLightAndDarkThemeMaps() throws {
        let configURL = temporaryDirectoryURL.appendingPathComponent("config.yaml")
        let configStore = ProjectConfigStore(configURL: configURL)
        var customLight = SpurwechselConfig.defaultTheme.light
        customLight.colors[.accent] = ThemeColor(hex: "#112233")!
        let config = SpurwechselConfig(
            projects: [],
            theme: ThemeSet(
                light: customLight,
                dark: SpurwechselConfig.defaultTheme.dark
            )
        )

        try configStore.save(UserConfigFile.explicit(from: config))
        let savedYAML = try String(contentsOf: configURL, encoding: .utf8)
        let savedConfig = try YAMLDecoder().decode(UserConfigFile.self, from: savedYAML)
        let lightTheme = try XCTUnwrap(savedConfig.theme?.light?.values)
        let darkTheme = try XCTUnwrap(savedConfig.theme?.dark?.values)

        XCTAssertEqual(lightTheme["accent"], "#112233")
        XCTAssertEqual(lightTheme["background"], "#F8FBFF")
        XCTAssertEqual(darkTheme["overlayStrong"], "#00000085")
    }

    func testConfigRoundTripPreservesCustomAgents() throws {
        let configURL = temporaryDirectoryURL.appendingPathComponent("config.yaml")
        let configStore = ProjectConfigStore(configURL: configURL)
        let customConfig = SpurwechselConfig(
            version: SpurwechselConfig.currentVersion,
            projects: [
                ProjectRecord(path: temporaryDirectoryURL.appendingPathComponent("alpha").path, name: "Alpha")
            ],
            agents: [
                AgentConfigRecord(name: "Claude Fast", command: "claude --model sonnet"),
                AgentConfigRecord(name: "Codex", command: "codex --sandbox workspace-write")
            ]
        )

        try configStore.save(UserConfigFile.explicit(from: customConfig))
        let loadedConfig = try configStore.load()

        XCTAssertEqual(loadedConfig.agents, customConfig.agents)
        XCTAssertEqual(loadedConfig.resolvedAgents.map(\.displayName), ["Claude Fast", "Codex"])
        XCTAssertEqual(loadedConfig.resolvedDefaultAgent.displayName, "Claude Fast")
    }

    func testConfigRoundTripPreservesDefaultAgentFlag() throws {
        let configURL = temporaryDirectoryURL.appendingPathComponent("config.yaml")
        let configStore = ProjectConfigStore(configURL: configURL)
        let customConfig = SpurwechselConfig(
            version: SpurwechselConfig.currentVersion,
            projects: [],
            agents: [
                AgentConfigRecord(name: "Claude", command: "claude --skip-permissions", isDefault: true),
                AgentConfigRecord(name: "Codex", command: "codex --sandbox workspace-write")
            ]
        )

        try configStore.save(UserConfigFile.explicit(from: customConfig))
        let loadedConfig = try configStore.load()

        XCTAssertEqual(loadedConfig.agents, customConfig.agents)
        XCTAssertEqual(loadedConfig.resolvedDefaultAgent.displayName, "Claude")
        XCTAssertEqual(loadedConfig.resolvedDefaultAgent.normalizedCommand, "claude --skip-permissions")
    }

    func testConfigRoundTripUsesFirstAgentAsResolvedDefaultWhenMissingFlag() throws {
        let configURL = temporaryDirectoryURL.appendingPathComponent("config.yaml")
        let configStore = ProjectConfigStore(configURL: configURL)
        let customConfig = SpurwechselConfig(
            version: SpurwechselConfig.currentVersion,
            projects: [],
            agents: [
                AgentConfigRecord(name: "Claude", command: "claude --print"),
                AgentConfigRecord(name: "Codex", command: "codex")
            ]
        )

        try configStore.save(UserConfigFile.explicit(from: customConfig))
        let loadedConfig = try configStore.load()

        XCTAssertEqual(loadedConfig.agents.count, 2)
        XCTAssertFalse(loadedConfig.agents[0].isDefault)
        XCTAssertFalse(loadedConfig.agents[1].isDefault)
        XCTAssertEqual(loadedConfig.resolvedDefaultAgent.displayName, "Claude")
    }

    func testResolvedDefaultAgentUsesFirstMarkedDefault() {
        let config = SpurwechselConfig(
            agents: [
                AgentConfigRecord(name: "One", command: "one"),
                AgentConfigRecord(name: "Two", command: "two", isDefault: true),
                AgentConfigRecord(name: "Three", command: "three", isDefault: true)
            ]
        )

        XCTAssertEqual(config.resolvedDefaultAgent.displayName, "Two")
    }

    func testConfigRoundTripPreservesCustomShortcutBinding() throws {
        let configURL = temporaryDirectoryURL.appendingPathComponent("config.yaml")
        let configStore = ProjectConfigStore(configURL: configURL)
        let customConfig = SpurwechselConfig(
            projects: [],
            shortcuts: [
                ShortcutRecord(
                    command: .toggleCommandBar,
                    key: "p",
                    modifiers: [.command, .shift]
                )
            ]
        )

        try configStore.save(UserConfigFile.explicit(from: customConfig))
        let loadedConfig = try configStore.load()

        XCTAssertEqual(loadedConfig.shortcuts, customConfig.shortcuts)
        XCTAssertEqual(
            loadedConfig.shortcutBinding(for: .toggleCommandBar)?.key,
            "p"
        )
        XCTAssertEqual(
            loadedConfig.shortcutBinding(for: .toggleCommandBar)?.modifiers,
            [.command, .shift]
        )
    }

    func testResolvedShortcutDisplayLabelUsesGlyphsAndUppercasesKey() {
        let binding = ResolvedShortcutBinding(
            command: .toggleCommandBar,
            key: "p",
            modifiers: [.command, .shift, .option]
        )

        XCTAssertEqual(binding?.displayLabel, "⌘⇧⌥P")
    }

    func testResolvedShortcutDisplayLabelPreservesModifierDisplayOrder() {
        let binding = ResolvedShortcutBinding(
            command: .createDefaultAgent,
            key: "t",
            modifiers: [.control, .option]
        )

        XCTAssertEqual(binding?.displayLabel, "⌥⌃T")
    }

    func testConfigRoundTripPreservesCustomCodeServerPort() throws {
        let configURL = temporaryDirectoryURL.appendingPathComponent("config.yaml")
        let configStore = ProjectConfigStore(configURL: configURL)
        let customConfig = SpurwechselConfig(
            codeServer: CodeServerConfig(port: 9091),
            projects: [],
            agents: SpurwechselConfig.defaultAgents,
            shortcuts: SpurwechselConfig.defaultShortcuts
        )

        try configStore.save(UserConfigFile.explicit(from: customConfig))
        let loadedConfig = try configStore.load()

        XCTAssertEqual(loadedConfig.codeServer.resolvedPort, 9091)
    }

    func testConfigRoundTripPreservesTerminalCommandKeyMapping() throws {
        let configURL = temporaryDirectoryURL.appendingPathComponent("config.yaml")
        let configStore = ProjectConfigStore(configURL: configURL)
        let customConfig = SpurwechselConfig(
            terminal: TerminalConfig(swapCommandAndControlWhenFocused: true)
        )

        try configStore.save(UserConfigFile.explicit(from: customConfig))
        let loadedConfig = try configStore.load()

        XCTAssertTrue(loadedConfig.terminal.swapCommandAndControlWhenFocused)
    }

    func testLoadConfigWithoutTerminalSectionFallsBackToDefaultTerminalMapping() throws {
        let configURL = temporaryDirectoryURL.appendingPathComponent("config.yaml")
        let configStore = ProjectConfigStore(configURL: configURL)
        let yaml = """
        version: 1
        projects:
          - path: "\(temporaryDirectoryURL.path)"
            name: "tmp"
        agents:
          - name: "claude"
            command: "claude"
            default: true
        """
        try yaml.appending("\n").write(to: configURL, atomically: true, encoding: .utf8)

        let loadedConfig = try configStore.load()

        XCTAssertFalse(loadedConfig.terminal.swapCommandAndControlWhenFocused)
    }

    func testLoadResultWithInvalidTerminalSectionReportsDiagnosticAndUsesDefaults() throws {
        let configURL = temporaryDirectoryURL.appendingPathComponent("config.yaml")
        let configStore = ProjectConfigStore(configURL: configURL)
        let yaml = """
        version: 1
        terminal:
          swapCommandAndControlWhenFocused: "yes"
        """
        try yaml.appending("\n").write(to: configURL, atomically: true, encoding: .utf8)

        let loadResult = configStore.loadResult()

        XCTAssertFalse(loadResult.config.terminal.swapCommandAndControlWhenFocused)
        XCTAssertTrue(loadResult.diagnostics.contains {
            $0.message.contains("could not be parsed")
        })
    }

    func testLoadConfigWithoutShortcutSectionFallsBackToDefaultResolvedShortcut() throws {
        let configURL = temporaryDirectoryURL.appendingPathComponent("config.yaml")
        let configStore = ProjectConfigStore(configURL: configURL)
        let yaml = """
        version: 1
        projects:
          - path: "\(temporaryDirectoryURL.path)"
            name: "tmp"
        agents:
          - name: "claude"
            command: "claude"
            default: true
        """
        try yaml.appending("\n").write(to: configURL, atomically: true, encoding: .utf8)

        let loadedConfig = try configStore.load()

        XCTAssertEqual(loadedConfig.shortcuts, [])
        XCTAssertEqual(
            loadedConfig.shortcutBinding(for: .toggleCommandBar)?.key,
            "k"
        )
        XCTAssertEqual(
            loadedConfig.shortcutBinding(for: .toggleCommandBar)?.modifiers,
            [.command]
        )
    }

    func testLoadResultWithInvalidCodeServerPortFallsBackToDefaultAndReportsDiagnostic() throws {
        let configURL = temporaryDirectoryURL.appendingPathComponent("config.yaml")
        let configStore = ProjectConfigStore(configURL: configURL)
        let yaml = """
        version: 1
        codeServer:
          port: 70000
        projects:
        agents:
        shortcuts:
        """
        try yaml.appending("\n").write(to: configURL, atomically: true, encoding: .utf8)

        let loadResult = configStore.loadResult()

        XCTAssertEqual(loadResult.config.codeServer.resolvedPort, CodeServerConfig.defaultPort)
        XCTAssertTrue(loadResult.diagnostics.contains {
            $0.message.contains("codeServer.port must be between 1 and 65535")
        })
    }

    func testLoadResultWithMalformedYAMLReportsDiagnosticAndUsesDefaults() throws {
        let configURL = temporaryDirectoryURL.appendingPathComponent("config.yaml")
        let configStore = ProjectConfigStore(configURL: configURL)
        let yaml = """
        version: 1
        projects:
          - path: "/tmp/repo"
            name: [broken
        """
        try yaml.appending("\n").write(to: configURL, atomically: true, encoding: .utf8)

        let loadResult = configStore.loadResult()

        XCTAssertEqual(loadResult.config.projects, [])
        XCTAssertEqual(loadResult.config.codeServer.resolvedPort, CodeServerConfig.defaultPort)
        XCTAssertTrue(loadResult.diagnostics.contains {
            $0.message.contains("could not be parsed")
        })
    }

    func testLoadResultWithInvalidRootReportsDiagnosticAndUsesDefaults() throws {
        let configURL = temporaryDirectoryURL.appendingPathComponent("config.yaml")
        let configStore = ProjectConfigStore(configURL: configURL)
        let yaml = """
        - not
        - a
        - mapping
        """
        try yaml.appending("\n").write(to: configURL, atomically: true, encoding: .utf8)

        let loadResult = configStore.loadResult()

        XCTAssertEqual(loadResult.config.projects, [])
        XCTAssertTrue(loadResult.diagnostics.contains {
            $0.message.contains("could not be parsed")
        })
    }

    func testLoadResultWithMissingProjectPathReportsDiagnosticAndSkipsProject() throws {
        let configURL = temporaryDirectoryURL.appendingPathComponent("config.yaml")
        let configStore = ProjectConfigStore(configURL: configURL)
        let yaml = """
        version: 1
        projects:
          - name: "Missing Path"
        """
        try yaml.appending("\n").write(to: configURL, atomically: true, encoding: .utf8)

        let loadResult = configStore.loadResult()

        XCTAssertEqual(loadResult.config.projects, [])
        XCTAssertTrue(loadResult.diagnostics.contains {
            $0.message.contains("projects[0].path is required")
        })
    }

    func testLoadResultWithInvalidAgentRecordReportsDiagnosticAndSkipsAgent() throws {
        let configURL = temporaryDirectoryURL.appendingPathComponent("config.yaml")
        let configStore = ProjectConfigStore(configURL: configURL)
        let yaml = """
        version: 1
        agents:
          - name: "Claude"
        """
        try yaml.appending("\n").write(to: configURL, atomically: true, encoding: .utf8)

        let loadResult = configStore.loadResult()

        XCTAssertEqual(loadResult.config.agents, [])
        XCTAssertTrue(loadResult.diagnostics.contains {
            $0.message.contains("agents[0].command is required")
        })
        XCTAssertEqual(loadResult.config.resolvedDefaultAgent.displayName, "opencode")
    }

    func testLoadResultWithUnsupportedShortcutModifierReportsDiagnosticAndDropsUnsupportedModifier() throws {
        let configURL = temporaryDirectoryURL.appendingPathComponent("config.yaml")
        let configStore = ProjectConfigStore(configURL: configURL)
        let yaml = """
        version: 1
        shortcuts:
          - command: "toggle-command-bar"
            key: "p"
            modifiers: ["command", "hyper"]
        """
        try yaml.appending("\n").write(to: configURL, atomically: true, encoding: .utf8)

        let loadResult = configStore.loadResult()

        XCTAssertEqual(loadResult.config.shortcuts.count, 1)
        XCTAssertEqual(loadResult.config.shortcuts[0].key, "p")
        XCTAssertEqual(loadResult.config.shortcuts[0].modifiers, [.command])
        XCTAssertTrue(loadResult.diagnostics.contains {
            $0.message.contains("unsupported value 'hyper'")
        })
    }

    func testExplicitShortcutSignatureOverridesConflictingDefaultShortcut() {
        let config = SpurwechselConfig(
            shortcuts: [
                ShortcutRecord(
                    command: .toggleLeftSidebar,
                    key: "p",
                    modifiers: [.command]
                )
            ]
        )

        XCTAssertEqual(
            config.shortcutBinding(for: .toggleLeftSidebar),
            ResolvedShortcutBinding(command: .toggleLeftSidebar, key: "p", modifiers: [.command])
        )
        XCTAssertNil(config.shortcutBinding(for: .selectProject))
    }

    func testImportedRecordsSkipDuplicatesAndNonDirectories() throws {
        let configStore = ProjectConfigStore(configURL: temporaryDirectoryURL.appendingPathComponent("config.yaml"))
        let existingDirectory = temporaryDirectoryURL.appendingPathComponent("existing", isDirectory: true)
        let newDirectory = temporaryDirectoryURL.appendingPathComponent("new", isDirectory: true)
        let notADirectory = temporaryDirectoryURL.appendingPathComponent("readme.txt", isDirectory: false)

        try FileManager.default.createDirectory(at: existingDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: notADirectory.path, contents: Data("hello".utf8))

        let existingRecords = [ProjectRecord(path: existingDirectory.path, name: "existing")]
        let importedRecords = configStore.importedRecords(
            from: [
                URL(fileURLWithPath: existingDirectory.path),
                URL(fileURLWithPath: "\(newDirectory.path)/."),
                URL(fileURLWithPath: notADirectory.path)
            ],
            existingRecords: existingRecords
        )

        XCTAssertEqual(importedRecords.count, 1)
        XCTAssertEqual(importedRecords.first?.path, newDirectory.path)
        XCTAssertEqual(importedRecords.first?.displayName, "new")
    }

    @MainActor
    func testStoreBootsProjectsFromPersistedConfig() async throws {
        let configURL = temporaryDirectoryURL.appendingPathComponent("config.yaml")
        let firstProjectPath = try createGitRepository(named: "first")
        let secondProjectPath = try createGitRepository(named: "second")

        let configStore = ProjectConfigStore(configURL: configURL)
        try configStore.save(
            UserConfigFile.explicit(from: SpurwechselConfig(
                projects: [
                    ProjectRecord(path: firstProjectPath.path, name: "First"),
                    ProjectRecord(path: secondProjectPath.path, name: "Second")
                ]
            ))
        )

        let store = TestStore(initialState: WorkspaceFeature.State(
            projects: ProjectsState.fromImportedProjects(
                [],
                collapsedProjectPaths: [],
                collapsedSectionIDs: []
            )
        )) {
            WorkspaceFeature()
        } withDependencies: { dependencies in
            dependencies.configClient.load = {
                configStore.loadResultEnsuringManagedFiles()
            }
            dependencies.configClient.normalizeDirectoryPath = { url in
                configStore.normalizeDirectoryPath(url)
            }
            dependencies.fileSystemClient.directoryExists = { path in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
                    && isDirectory.boolValue
            }
            dependencies.gitClient.repositorySnapshot = { url in
                try await GitRepositoryService().repositorySnapshot(at: url)
            }
        }
        store.exhaustivity = .off

        await store.send(WorkspaceFeature.Action.refreshRequested(
            preferredSelection: Optional<WorkspaceSelection>.none,
            revealSidebars: false,
            activateMainWindow: false,
            reportErrors: true
        ))
        await store.receive { action in
            guard case ._projectsLoaded = action else {
                return false
            }
            return true
        }

        XCTAssertEqual(store.state.projects.projects.map { $0.name }, ["First", "Second"])
        XCTAssertEqual(store.state.projects.projects.map { $0.branch }, ["main", "main"])

        if case let .project(selectedID) = store.state.projects.selection {
            XCTAssertEqual(selectedID, store.state.projects.projects.first?.id)
        } else {
            XCTFail("Expected project selection after loading persisted projects")
        }
    }

    @MainActor
    func testStoreLeavesConfigUntouchedWhenShortcutSectionMissing() throws {
        let configURL = temporaryDirectoryURL.appendingPathComponent("config.yaml")
        let firstProjectPath = try createGitRepository(named: "first")
        let yaml = """
        version: 1
        projects:
          - path: "\(firstProjectPath.path)"
            name: "First"
        agents:
          - name: "claude"
            command: "claude"
            default: true
        """
        try yaml.appending("\n").write(to: configURL, atomically: true, encoding: .utf8)

        let configStore = ProjectConfigStore(configURL: configURL)
        let originalContents = try String(contentsOf: configURL, encoding: .utf8)
        let loadResult = configStore.loadResultEnsuringManagedFiles()

        let savedConfig = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertEqual(savedConfig, originalContents)
        XCTAssertTrue(loadResult.diagnostics.isEmpty)
        XCTAssertEqual(
            loadResult.config.shortcutBinding(for: .toggleCommandBar),
            ResolvedShortcutBinding(command: .toggleCommandBar, key: "k", modifiers: [.command])
        )
    }

    @MainActor
    func testStoreLeavesConfigUntouchedWhenCodeServerSectionMissing() throws {
        let configURL = temporaryDirectoryURL.appendingPathComponent("config.yaml")
        let firstProjectPath = try createGitRepository(named: "first")
        let yaml = """
        version: 1
        projects:
          - path: "\(firstProjectPath.path)"
            name: "First"
        agents:
          - name: "claude"
            command: "claude"
            default: true
        shortcuts:
          - command: "toggle-command-bar"
            key: "k"
            modifiers: ["command"]
        """
        try yaml.appending("\n").write(to: configURL, atomically: true, encoding: .utf8)

        let configStore = ProjectConfigStore(configURL: configURL)
        let originalContents = try String(contentsOf: configURL, encoding: .utf8)
        _ = configStore.loadResultEnsuringManagedFiles()

        let savedConfig = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertEqual(savedConfig, originalContents)
    }

    @MainActor
    func testStoreBootstrapsManagedConfigArtifactsOnInit() throws {
        let configURL = temporaryDirectoryURL
            .appendingPathComponent(".spurwechsel", isDirectory: true)
            .appendingPathComponent("config.yaml")
        let configStore = ProjectConfigStore(configURL: configURL)

        _ = configStore.loadResultEnsuringManagedFiles()

        let agentsURL = configURL.deletingLastPathComponent().appendingPathComponent("AGENTS.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: agentsURL.path))
    }

    private func createGitRepository(named name: String) throws -> URL {
        let repositoryURL = temporaryDirectoryURL.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)

        try runGit(arguments: ["init", "--initial-branch", "main"], in: repositoryURL)
        try runGit(arguments: ["config", "user.name", "Spurwechsel Tests"], in: repositoryURL)
        try runGit(arguments: ["config", "user.email", "tests@example.com"], in: repositoryURL)

        let readmeURL = repositoryURL.appendingPathComponent("README.md")
        try "hello".write(to: readmeURL, atomically: true, encoding: .utf8)
        try runGit(arguments: ["add", "README.md"], in: repositoryURL)
        try runGit(arguments: ["commit", "-m", "init"], in: repositoryURL)

        return repositoryURL
    }

    private func runGit(arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = directory

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: stderrData, encoding: .utf8) ?? "git command failed"
            XCTFail(message)
            throw NSError(domain: "ProjectConfigStoreTests", code: Int(process.terminationStatus))
        }
    }

    private func shortcutsByCommand(_ shortcuts: [ShortcutRecord]) -> [CommandID: ShortcutRecord] {
        Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.command, $0) })
    }
}

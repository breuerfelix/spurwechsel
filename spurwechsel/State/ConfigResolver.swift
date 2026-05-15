import Foundation

struct ConfigDomainResult<Value> {
    var value: Value
    var diagnostics: [ConfigDiagnostic]

    init(value: Value, diagnostics: [ConfigDiagnostic] = []) {
        self.value = value
        self.diagnostics = diagnostics
    }
}

struct ConfigResolver {
    let normalizeDirectoryPath: (URL) -> String

    func resolve(
        fileConfig: UserConfigFile,
        diagnostics initialDiagnostics: [ConfigDiagnostic] = []
    ) -> ConfigLoadResult {
        let versionResult = resolveVersion(fileConfig.version)
        let codeServerResult = resolveCodeServer(fileConfig.codeServer)
        let projectsResult = resolveProjects(fileConfig.projects)
        let agentsResult = resolveAgents(fileConfig.agents)
        let shortcutsResult = resolveShortcuts(fileConfig.shortcuts)
        let terminalResult = resolveTerminal(fileConfig.terminal)
        let themeResult = resolveTheme(fileConfig.theme)

        return ConfigLoadResult(
            fileConfig: ConfigFileNormalizer(normalizeDirectoryPath: normalizeDirectoryPath).normalize(fileConfig),
            config: SpurwechselConfig(
                version: versionResult.value,
                codeServer: codeServerResult.value,
                projects: projectsResult.value,
                agents: agentsResult.value,
                shortcuts: shortcutsResult.value,
                terminal: terminalResult.value,
                theme: themeResult.value
            ),
            diagnostics: initialDiagnostics
                + versionResult.diagnostics
                + codeServerResult.diagnostics
                + projectsResult.diagnostics
                + agentsResult.diagnostics
                + shortcutsResult.diagnostics
                + terminalResult.diagnostics
                + themeResult.diagnostics
        )
    }

    private func resolveVersion(_ version: Int?) -> ConfigDomainResult<Int> {
        guard let version else {
            return ConfigDomainResult(value: SpurwechselConfig.currentVersion)
        }

        guard version > 0 else {
            return ConfigDomainResult(
                value: SpurwechselConfig.currentVersion,
                diagnostics: [ConfigDiagnostic("Config version must be greater than zero. Using version \(SpurwechselConfig.currentVersion).")]
            )
        }

        return ConfigDomainResult(value: version)
    }

    private func resolveCodeServer(_ codeServer: UserCodeServerConfig?) -> ConfigDomainResult<CodeServerConfig> {
        guard let configuredPort = codeServer?.port else {
            return ConfigDomainResult(value: CodeServerConfig())
        }

        guard (1 ... 65535).contains(configuredPort) else {
            return ConfigDomainResult(
                value: CodeServerConfig(),
                diagnostics: [
                    ConfigDiagnostic(
                        "codeServer.port must be between 1 and 65535. Using default port \(CodeServerConfig.defaultPort)."
                    )
                ]
            )
        }

        return ConfigDomainResult(value: CodeServerConfig(port: configuredPort))
    }

    private func resolveProjects(_ projects: [UserProjectRecord]?) -> ConfigDomainResult<[ProjectRecord]> {
        guard let projects else {
            return ConfigDomainResult(value: [])
        }

        var diagnostics: [ConfigDiagnostic] = []
        var records: [ProjectRecord] = []

        for (index, project) in projects.enumerated() {
            guard let rawPath = project.path?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawPath.isEmpty else {
                diagnostics.append(ConfigDiagnostic("projects[\(index)].path is required."))
                continue
            }

            let normalizedPath = normalizeDirectoryPath(URL(fileURLWithPath: rawPath))
            let name = project.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            records.append(
                ProjectRecord(
                    path: normalizedPath,
                    name: name?.isEmpty == true ? nil : name
                )
            )
        }

        return ConfigDomainResult(
            value: deduplicatedProjects(records),
            diagnostics: diagnostics
        )
    }

    private func resolveAgents(_ agents: [UserAgentConfigRecord]?) -> ConfigDomainResult<[AgentConfigRecord]> {
        guard let agents else {
            return ConfigDomainResult(value: [])
        }

        var diagnostics: [ConfigDiagnostic] = []
        var records: [AgentConfigRecord] = []

        for (index, agent) in agents.enumerated() {
            guard let rawName = agent.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawName.isEmpty else {
                diagnostics.append(ConfigDiagnostic("agents[\(index)].name is required."))
                continue
            }

            guard let rawCommand = agent.command?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawCommand.isEmpty else {
                diagnostics.append(ConfigDiagnostic("agents[\(index)].command is required."))
                continue
            }

            records.append(
                AgentConfigRecord(
                    name: rawName,
                    command: rawCommand,
                    isDefault: agent.isDefault ?? false
                )
            )
        }

        return ConfigDomainResult(
            value: deduplicatedAgents(records),
            diagnostics: diagnostics
        )
    }

    private func resolveShortcuts(_ shortcuts: [UserShortcutRecord]?) -> ConfigDomainResult<[ShortcutRecord]> {
        guard let shortcuts else {
            return ConfigDomainResult(value: [])
        }

        var diagnostics: [ConfigDiagnostic] = []
        var records: [ShortcutRecord] = []

        for (index, shortcut) in shortcuts.enumerated() {
            guard let rawCommand = shortcut.command?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawCommand.isEmpty else {
                diagnostics.append(ConfigDiagnostic("shortcuts[\(index)].command is required."))
                continue
            }

            guard let command = CommandID(rawValue: rawCommand) else {
                diagnostics.append(ConfigDiagnostic("shortcuts[\(index)].command is invalid."))
                continue
            }

            guard let rawKey = shortcut.key?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawKey.isEmpty else {
                diagnostics.append(ConfigDiagnostic("shortcuts[\(index)].key is required."))
                continue
            }

            let modifiers = resolveShortcutModifiers(shortcut.modifiers, index: index, diagnostics: &diagnostics)
            records.append(
                ShortcutRecord(
                    command: command,
                    key: rawKey,
                    modifiers: modifiers
                )
            )
        }

        return ConfigDomainResult(
            value: deduplicatedShortcuts(records),
            diagnostics: diagnostics
        )
    }

    private func resolveShortcutModifiers(
        _ modifiers: [String]?,
        index: Int,
        diagnostics: inout [ConfigDiagnostic]
    ) -> [ShortcutModifier] {
        guard let modifiers else {
            return []
        }

        var resolvedModifiers: [ShortcutModifier] = []
        for modifier in modifiers {
            let normalizedModifier = modifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let resolvedModifier = ShortcutModifier(rawValue: normalizedModifier) else {
                diagnostics.append(
                    ConfigDiagnostic(
                        "shortcuts[\(index)].modifiers contains unsupported value '\(modifier)'."
                    )
                )
                continue
            }
            resolvedModifiers.append(resolvedModifier)
        }

        return resolvedModifiers
    }

    private func deduplicatedProjects(_ records: [ProjectRecord]) -> [ProjectRecord] {
        var seenPaths = Set<String>()
        var dedupedRecords: [ProjectRecord] = []

        for record in records {
            guard !seenPaths.contains(record.path) else {
                continue
            }
            seenPaths.insert(record.path)
            dedupedRecords.append(record)
        }

        return dedupedRecords
    }

    private func deduplicatedAgents(_ agents: [AgentConfigRecord]) -> [AgentConfigRecord] {
        var seenPairs = Set<String>()
        var dedupedAgents: [AgentConfigRecord] = []

        for agent in agents {
            let key = "\(agent.displayName.lowercased())::\(agent.normalizedCommand)"
            guard !seenPairs.contains(key) else {
                continue
            }
            seenPairs.insert(key)
            dedupedAgents.append(agent)
        }

        return dedupedAgents
    }

    private func deduplicatedShortcuts(_ shortcuts: [ShortcutRecord]) -> [ShortcutRecord] {
        var recordsByCommand: [CommandID: ShortcutRecord] = [:]
        for shortcut in shortcuts {
            recordsByCommand[shortcut.command] = shortcut
        }

        return CommandID.allCases.compactMap { recordsByCommand[$0] }
    }

    private func resolveTerminal(_ terminal: UserTerminalConfig?) -> ConfigDomainResult<TerminalConfig> {
        ConfigDomainResult(
            value: TerminalConfig(
                commandKeyMapsToControl: terminal?.commandKeyMapsToControl ?? false
            )
        )
    }

    private func resolveTheme(_ theme: UserThemeConfig?) -> ConfigDomainResult<ThemeSet> {
        let defaultTheme = SpurwechselConfig.defaultTheme
        let lightResult = resolveThemePalette(
            theme?.light,
            modeName: "light",
            defaults: defaultTheme.light
        )
        let darkResult = resolveThemePalette(
            theme?.dark,
            modeName: "dark",
            defaults: defaultTheme.dark
        )

        return ConfigDomainResult(
            value: ThemeSet(light: lightResult.value, dark: darkResult.value),
            diagnostics: lightResult.diagnostics + darkResult.diagnostics
        )
    }

    private func resolveThemePalette(
        _ palette: UserThemePalette?,
        modeName: String,
        defaults: ThemePalette
    ) -> ConfigDomainResult<ThemePalette> {
        guard let palette else {
            return ConfigDomainResult(value: defaults)
        }

        var diagnostics: [ConfigDiagnostic] = []
        var overrides: [ThemeToken: ThemeColor] = [:]

        for (rawToken, rawValue) in palette.values {
            guard let token = ThemeToken(rawValue: rawToken) else {
                diagnostics.append(
                    ConfigDiagnostic("theme.\(modeName).\(rawToken) is unsupported and was ignored.")
                )
                continue
            }

            guard let color = ThemeColor(hex: rawValue) else {
                diagnostics.append(
                    ConfigDiagnostic("theme.\(modeName).\(rawToken) must be #RRGGBB or #RRGGBBAA. Using default.")
                )
                continue
            }
            overrides[token] = color
        }

        return ConfigDomainResult(
            value: ThemePalette(defaultingTo: defaults, overrides: overrides),
            diagnostics: diagnostics
        )
    }
}

struct ConfigFileNormalizer {
    let normalizeDirectoryPath: (URL) -> String

    func normalize(_ fileConfig: UserConfigFile) -> UserConfigFile {
        UserConfigFile(
            version: fileConfig.version,
            codeServer: fileConfig.codeServer,
            projects: normalizedProjects(fileConfig.projects),
            agents: normalizedAgents(fileConfig.agents),
            shortcuts: normalizedShortcuts(fileConfig.shortcuts),
            terminal: normalizedTerminal(fileConfig.terminal),
            theme: normalizedTheme(fileConfig.theme)
        )
    }

    private func normalizedProjects(_ projects: [UserProjectRecord]?) -> [UserProjectRecord]? {
        guard let projects else {
            return nil
        }

        var seenPaths = Set<String>()
        var normalizedProjects: [UserProjectRecord] = []

        for project in projects {
            guard let rawPath = project.path?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawPath.isEmpty else {
                continue
            }

            let normalizedPath = normalizeDirectoryPath(URL(fileURLWithPath: rawPath))
            guard !seenPaths.contains(normalizedPath) else {
                continue
            }

            seenPaths.insert(normalizedPath)
            let name = project.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            normalizedProjects.append(
                UserProjectRecord(
                    path: normalizedPath,
                    name: name?.isEmpty == true ? nil : name
                )
            )
        }

        return normalizedProjects
    }

    private func normalizedAgents(_ agents: [UserAgentConfigRecord]?) -> [UserAgentConfigRecord]? {
        guard let agents else {
            return nil
        }

        var seenPairs = Set<String>()
        var normalizedAgents: [UserAgentConfigRecord] = []

        for agent in agents {
            guard let name = agent.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty,
                  let command = agent.command?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !command.isEmpty else {
                continue
            }

            let key = "\(name.lowercased())::\(command)"
            guard !seenPairs.contains(key) else {
                continue
            }

            seenPairs.insert(key)
            normalizedAgents.append(
                UserAgentConfigRecord(
                    name: name,
                    command: command,
                    isDefault: agent.isDefault == true ? true : nil
                )
            )
        }

        return normalizedAgents
    }

    private func normalizedShortcuts(_ shortcuts: [UserShortcutRecord]?) -> [UserShortcutRecord]? {
        guard let shortcuts else {
            return nil
        }

        var recordsByCommand: [CommandID: UserShortcutRecord] = [:]

        for shortcut in shortcuts {
            guard let rawCommand = shortcut.command?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let command = CommandID(rawValue: rawCommand),
                  let key = shortcut.key?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !key.isEmpty else {
                continue
            }

            let modifiers = (shortcut.modifiers ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .compactMap(ShortcutModifier.init(rawValue:))
                .map(\.rawValue)

            recordsByCommand[command] = UserShortcutRecord(
                command: command.rawValue,
                key: key,
                modifiers: modifiers
            )
        }

        return CommandID.allCases.compactMap { recordsByCommand[$0] }
    }

    private func normalizedTheme(_ theme: UserThemeConfig?) -> UserThemeConfig? {
        guard let theme else {
            return nil
        }

        return UserThemeConfig(
            light: normalizedThemePalette(theme.light),
            dark: normalizedThemePalette(theme.dark)
        )
    }

    private func normalizedThemePalette(_ palette: UserThemePalette?) -> UserThemePalette? {
        guard let palette else {
            return nil
        }

        var normalized: [String: String] = [:]
        for (rawToken, rawValue) in palette.values {
            let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty, !value.isEmpty else {
                continue
            }
            normalized[token] = value
        }
        return UserThemePalette(values: normalized)
    }

    private func normalizedTerminal(_ terminal: UserTerminalConfig?) -> UserTerminalConfig? {
        guard let terminal else {
            return nil
        }
        return UserTerminalConfig(
            commandKeyMapsToControl: terminal.commandKeyMapsToControl
        )
    }
}

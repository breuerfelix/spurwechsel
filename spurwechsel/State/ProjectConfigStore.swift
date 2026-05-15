import Foundation
import Yams

struct ProjectConfigStore {
    let configURL: URL
    private let fileManager: FileManager
    private static let managedAgentsFileName = "AGENTS.md"

    init(
        configURL: URL = ProjectConfigStore.defaultConfigURL(),
        fileManager: FileManager = .default
    ) {
        self.configURL = configURL
        self.fileManager = fileManager
    }

    static func defaultConfigURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let explicitPath = environment["SPURWECHSEL_CONFIG_PATH"], !explicitPath.isEmpty {
            return URL(fileURLWithPath: explicitPath)
        }

        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".spurwechsel", isDirectory: true)
            .appendingPathComponent("config.yaml", isDirectory: false)
    }

    func load() throws -> SpurwechselConfig {
        loadResult().config
    }

    func loadResultEnsuringManagedFiles() -> ConfigLoadResult {
        do {
            try synchronizeManagedFiles()
        } catch {
            return defaultLoadResult(
                "Failed to prepare managed config files at \(configURL.path): \(error.localizedDescription). Using defaults."
            )
        }

        return loadResult()
    }

    func loadResult() -> ConfigLoadResult {
        guard fileManager.fileExists(atPath: configURL.path) else {
            return ConfigResolver(
                normalizeDirectoryPath: normalizeDirectoryPath
            ).resolve(fileConfig: UserConfigFile())
        }

        let data: Data
        do {
            data = try Data(contentsOf: configURL)
        } catch {
            return defaultLoadResult(
                "Failed to read config at \(configURL.path). Using defaults."
            )
        }

        guard let text = String(data: data, encoding: .utf8) else {
            return defaultLoadResult(
                "Config at \(configURL.path) is not valid UTF-8. Using defaults."
            )
        }

        return decodeLoadedConfig(text)
    }

    func save(_ fileConfig: UserConfigFile) throws {
        try writeConfigFile(fileConfig)
        try synchronizeAgentsInstructionsFile()
    }

    func normalizeDirectoryPath(_ url: URL) -> String {
        let normalizedURL = url.standardizedFileURL.resolvingSymlinksInPath()
        return normalizedURL.path
    }

    func importedRecords(
        from urls: [URL],
        existingRecords: [ProjectRecord]
    ) -> [ProjectRecord] {
        var knownPaths = Set(existingRecords.map(\.path))
        var newRecords: [ProjectRecord] = []

        for url in urls {
            let normalizedPath = normalizeDirectoryPath(url)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: normalizedPath, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }
            guard !knownPaths.contains(normalizedPath) else {
                continue
            }

            knownPaths.insert(normalizedPath)
            let defaultName = URL(fileURLWithPath: normalizedPath).lastPathComponent
            newRecords.append(
                ProjectRecord(
                    path: normalizedPath,
                    name: defaultName
                )
            )
        }

        return newRecords
    }

    private func decodeLoadedConfig(_ yaml: String) -> ConfigLoadResult {
        do {
            let fileConfig = try YAMLDecoder().decode(UserConfigFile.self, from: yaml)
            return ConfigResolver(
                normalizeDirectoryPath: normalizeDirectoryPath
            ).resolve(fileConfig: fileConfig)
        } catch {
            return defaultLoadResult(
                "Config YAML could not be parsed at \(configURL.path): \(error.localizedDescription). Using defaults."
            )
        }
    }

    private func defaultLoadResult(_ message: String) -> ConfigLoadResult {
        ConfigResolver(
            normalizeDirectoryPath: normalizeDirectoryPath
        ).resolve(
            fileConfig: UserConfigFile(),
            diagnostics: [ConfigDiagnostic(message)]
        )
    }

    private var parentDirectoryURL: URL {
        configURL.deletingLastPathComponent()
    }

    private var agentsInstructionsURL: URL {
        parentDirectoryURL.appendingPathComponent(Self.managedAgentsFileName, isDirectory: false)
    }

    private func synchronizeManagedFiles() throws {
        try fileManager.createDirectory(at: parentDirectoryURL, withIntermediateDirectories: true)

        if !fileManager.fileExists(atPath: configURL.path) {
            try writeConfigFile(UserConfigFile.explicit(from: SpurwechselConfig()))
        }

        try synchronizeAgentsInstructionsFile()
    }

    private func writeConfigFile(_ fileConfig: UserConfigFile) throws {
        try fileManager.createDirectory(at: parentDirectoryURL, withIntermediateDirectories: true)

        let normalizedConfig = ConfigFileNormalizer(
            normalizeDirectoryPath: normalizeDirectoryPath
        ).normalize(fileConfig)
        let yaml = try YAMLEncoder().encode(normalizedConfig)
        guard let data = yaml.data(using: .utf8) else {
            throw ConfigError.invalidEncoding
        }

        try data.write(to: configURL, options: .atomic)
    }

    private func synchronizeAgentsInstructionsFile() throws {
        let renderedInstructions = Self.renderedAgentsInstructions()
        if let existingContent = try? String(contentsOf: agentsInstructionsURL, encoding: .utf8),
           existingContent == renderedInstructions {
            return
        }

        try renderedInstructions.write(
            to: agentsInstructionsURL,
            atomically: true,
            encoding: .utf8
        )
    }

    private static func renderedAgentsInstructions() -> String {
        let commands = CommandID.allCases
            .map { "- `\($0.rawValue)`" }
            .joined(separator: "\n")
        let defaultShortcuts = SpurwechselConfig.defaultShortcuts
            .compactMap { shortcut -> String? in
                guard let binding = ResolvedShortcutBinding(record: shortcut) else {
                    return nil
                }
                return "- `\(binding.displayLabel)`: `\(shortcut.command.rawValue)`"
            }
            .joined(separator: "\n")
        let themeTokens = ThemeToken.allCases
            .map { "- `\($0.rawValue)`" }
            .joined(separator: "\n")

        return """
        # Spurwechsel Agent Config Guide

        This file is managed by Spurwechsel.
        Manual edits may be overwritten when app updates or config is saved.

        Configure app by editing `config.yaml` in same folder.
        Keep YAML valid and keep values inside supported schema below.

        ## Supported top-level keys

        - `version`
        - `codeServer`
        - `sections`
        - `projects`
        - `agents`
        - `shortcuts`
        - `terminal`
        - `theme`

        ## Configurable fields

        - `version`: positive integer.
        - `codeServer.port`: integer from `1` to `65535`.
        - `sections[]`: `id` (required), `name` (optional). Section id `other` is reserved.
        - `projects[]`: `path` (required), `name` (optional), `sections` (optional list of section ids).
        - `agents[]`: `name` (required), `command` (required), `default` (optional bool).
        - `shortcuts[]`: `command` (required), `key` (required single character), `modifiers` (optional list).
        - `terminal.commandKeyMapsToControl`: optional bool, default `false`.
        - `theme.light.<token>` and `theme.dark.<token>`: color string `#RRGGBB` or `#RRGGBBAA`.

        ## Important rules

        - `projects` store repository roots only. Worktrees are discovered from git.
        - `projects[].sections` must reference ids from `sections[]`.
        - If project has no valid sections, sidebar places it in fallback section `other`.
        - If no valid agents remain, Spurwechsel falls back to built-ins (`opencode`, `claude`, `codex`).
        - `shortcuts[].modifiers` supports only: `command`, `shift`, `option`, `control`.
        - Invalid values trigger diagnostics and fallback values.

        ## Default shortcut bindings

        These defaults apply when `shortcuts` is omitted. If user defines shortcut with same key+modifier signature, explicit config wins and conflicting default is dropped.

        \(defaultShortcuts)

        ## Supported shortcut command IDs

        \(commands)

        ## Supported theme tokens

        \(themeTokens)

        ## Example

        ```yaml
        version: 1
        codeServer:
          port: 8080
        sections:
          - id: active
            name: "Active"
          - id: experiments
            name: "Experiments"
        projects:
          - path: "/Users/me/code/project"
            name: "Project"
            sections: [active, experiments]
        agents:
          - name: opencode
            command: opencode
            default: true
          - name: claude
            command: claude
          - name: codex
            command: codex
        shortcuts:
          - command: toggle-command-bar
            key: k
            modifiers: [command]
          - command: create-default-agent
            key: t
            modifiers: [command]
          - command: select-next-agent
            key: j
            modifiers: [command, shift]
          - command: select-previous-agent
            key: k
            modifiers: [command, shift]
          - command: select-project
            key: p
            modifiers: [command]
          - command: delete-agent
            key: w
            modifiers: [command]
          - command: toggle-preview-pane
            key: s
            modifiers: [command, shift]
          - command: open-agent-view
            key: u
            modifiers: [command, shift]
          - command: open-terminal-view
            key: i
            modifiers: [command, shift]
          - command: open-vscode-view
            key: o
            modifiers: [command, shift]
        terminal:
          commandKeyMapsToControl: false
        theme: {}
        ```
        """
    }
}

extension ProjectConfigStore {
    enum ConfigError: Error {
        case invalidEncoding
    }
}

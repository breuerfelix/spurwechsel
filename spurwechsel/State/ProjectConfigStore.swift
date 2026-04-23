import Foundation
import Yams

struct ProjectConfigStore {
    let configURL: URL
    private let fileManager: FileManager

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
        let parentDirectory = configURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

        let normalizedConfig = ConfigFileNormalizer(
            normalizeDirectoryPath: normalizeDirectoryPath
        ).normalize(fileConfig)
        let yaml = try YAMLEncoder().encode(normalizedConfig)
        guard let data = yaml.data(using: .utf8) else {
            throw ConfigError.invalidEncoding
        }

        try data.write(to: configURL, options: .atomic)
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
}

extension ProjectConfigStore {
    enum ConfigError: Error {
        case invalidEncoding
    }
}

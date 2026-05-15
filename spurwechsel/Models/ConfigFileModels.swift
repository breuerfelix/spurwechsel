import Foundation

struct ConfigDiagnostic: Equatable, Hashable {
    var message: String

    init(_ message: String) {
        self.message = message
    }
}

struct ConfigLoadResult: Equatable {
    var fileConfig: UserConfigFile
    var config: SpurwechselConfig
    var diagnostics: [ConfigDiagnostic]

    var hasIssues: Bool {
        !diagnostics.isEmpty
    }
}

struct UserConfigFile: Codable, Equatable {
    var version: Int?
    var codeServer: UserCodeServerConfig?
    var sections: [UserProjectSectionRecord]?
    var projects: [UserProjectRecord]?
    var agents: [UserAgentConfigRecord]?
    var shortcuts: [UserShortcutRecord]?
    var terminal: UserTerminalConfig?
    var theme: UserThemeConfig?

    init(
        version: Int? = nil,
        codeServer: UserCodeServerConfig? = nil,
        sections: [UserProjectSectionRecord]? = nil,
        projects: [UserProjectRecord]? = nil,
        agents: [UserAgentConfigRecord]? = nil,
        shortcuts: [UserShortcutRecord]? = nil,
        terminal: UserTerminalConfig? = nil,
        theme: UserThemeConfig? = nil
    ) {
        self.version = version
        self.codeServer = codeServer
        self.sections = sections
        self.projects = projects
        self.agents = agents
        self.shortcuts = shortcuts
        self.terminal = terminal
        self.theme = theme
    }

    static func explicit(from config: SpurwechselConfig) -> UserConfigFile {
        UserConfigFile(
            version: config.version,
            codeServer: UserCodeServerConfig(port: config.codeServer.resolvedPort),
            sections: config.sections.map {
                UserProjectSectionRecord(
                    id: $0.id,
                    name: $0.name
                )
            },
            projects: config.projects.map {
                UserProjectRecord(
                    path: $0.path,
                    name: $0.name,
                    sections: $0.sections
                )
            },
            agents: config.agents.map {
                UserAgentConfigRecord(
                    name: $0.name,
                    command: $0.command,
                    isDefault: $0.isDefault ? true : nil
                )
            },
            shortcuts: config.shortcuts.map {
                UserShortcutRecord(
                    command: $0.command.rawValue,
                    key: $0.key,
                    modifiers: $0.modifiers.map(\.rawValue)
                )
            },
            terminal: UserTerminalConfig(
                swapCommandAndControlWhenFocused: config.terminal.swapCommandAndControlWhenFocused
            ),
            theme: UserThemeConfig(
                light: UserThemePalette(values: config.theme.light.asHexMap),
                dark: UserThemePalette(values: config.theme.dark.asHexMap)
            )
        )
    }
}

struct UserCodeServerConfig: Codable, Equatable {
    var port: Int?

    init(port: Int? = nil) {
        self.port = port
    }
}

struct UserTerminalConfig: Codable, Equatable {
    var swapCommandAndControlWhenFocused: Bool?

    init(swapCommandAndControlWhenFocused: Bool? = nil) {
        self.swapCommandAndControlWhenFocused = swapCommandAndControlWhenFocused
    }
}

struct UserProjectRecord: Codable, Equatable, Hashable {
    var path: String?
    var name: String?
    var sections: [String]?

    init(path: String? = nil, name: String? = nil, sections: [String]? = nil) {
        self.path = path
        self.name = name
        self.sections = sections
    }

    init(record: ProjectRecord) {
        self.path = record.path
        self.name = record.name
        self.sections = record.sections
    }

}

struct UserProjectSectionRecord: Codable, Equatable, Hashable {
    var id: String?
    var name: String?

    init(id: String? = nil, name: String? = nil) {
        self.id = id
        self.name = name
    }

    init(record: ProjectSectionRecord) {
        self.id = record.id
        self.name = record.name
    }
}

struct UserAgentConfigRecord: Codable, Equatable, Hashable {
    var name: String?
    var command: String?
    var isDefault: Bool?

    enum CodingKeys: String, CodingKey {
        case name
        case command
        case isDefault = "default"
    }

    init(name: String? = nil, command: String? = nil, isDefault: Bool? = nil) {
        self.name = name
        self.command = command
        self.isDefault = isDefault
    }

    init(record: AgentConfigRecord) {
        self.name = record.name
        self.command = record.command
        self.isDefault = record.isDefault ? true : nil
    }

}

struct UserShortcutRecord: Codable, Equatable, Hashable {
    var command: String?
    var key: String?
    var modifiers: [String]?

    init(
        command: String? = nil,
        key: String? = nil,
        modifiers: [String]? = nil
    ) {
        self.command = command
        self.key = key
        self.modifiers = modifiers
    }

    init(record: ShortcutRecord) {
        self.command = record.command.rawValue
        self.key = record.key
        self.modifiers = record.modifiers.map(\.rawValue)
    }
}

struct UserThemeConfig: Codable, Equatable {
    var light: UserThemePalette?
    var dark: UserThemePalette?

    init(light: UserThemePalette? = nil, dark: UserThemePalette? = nil) {
        self.light = light
        self.dark = dark
    }
}

struct UserThemePalette: Codable, Equatable {
    var values: [String: String]

    init(values: [String: String] = [:]) {
        self.values = values
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var values: [String: String] = [:]
        for key in container.allKeys {
            if let value = try? container.decode(String.self, forKey: key) {
                values[key.stringValue] = value
            }
        }
        self.values = values
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        for key in values.keys.sorted() {
            guard let codingKey = DynamicCodingKey(stringValue: key),
                  let value = values[key]
            else {
                continue
            }
            try container.encode(value, forKey: codingKey)
        }
    }
}

private struct DynamicCodingKey: CodingKey, Hashable {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

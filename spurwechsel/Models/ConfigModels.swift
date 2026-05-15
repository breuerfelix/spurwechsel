import Foundation

enum ShortcutModifier: String, CaseIterable, Hashable, Codable {
    case command
    case shift
    case option
    case control
}

struct ShortcutRecord: Equatable, Hashable {
    var command: CommandID
    var key: String
    var modifiers: [ShortcutModifier]

    init(
        command: CommandID,
        key: String,
        modifiers: [ShortcutModifier]
    ) {
        self.command = command
        self.key = key
        self.modifiers = modifiers
    }
}

struct ResolvedShortcutBinding: Equatable, Hashable {
    var command: CommandID
    var key: String
    var modifiers: Set<ShortcutModifier>

    init?(
        command: CommandID,
        key: String,
        modifiers: Set<ShortcutModifier>
    ) {
        let normalizedKey = Self.normalizeKey(key)
        guard normalizedKey.count == 1 else {
            return nil
        }
        self.command = command
        self.key = normalizedKey
        self.modifiers = modifiers
    }

    init?(record: ShortcutRecord) {
        self.init(
            command: record.command,
            key: record.key,
            modifiers: Set(record.modifiers)
        )
    }

    var signature: String {
        let modifierPart = modifiers
            .map(\.rawValue)
            .sorted()
            .joined(separator: "+")
        return "\(modifierPart)::\(key)"
    }

    var displayLabel: String {
        let modifierGlyphs = ShortcutModifier.displayOrder.compactMap { modifier -> String? in
            guard modifiers.contains(modifier) else {
                return nil
            }
            return modifier.glyph
        }
        return modifierGlyphs.joined() + key.uppercased()
    }

    static func normalizeKey(_ rawKey: String) -> String {
        rawKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

private extension ShortcutModifier {
    static let displayOrder: [ShortcutModifier] = [
        .command,
        .shift,
        .option,
        .control
    ]

    var glyph: String {
        switch self {
        case .command:
            return "⌘"
        case .shift:
            return "⇧"
        case .option:
            return "⌥"
        case .control:
            return "⌃"
        }
    }
}

struct AgentConfigRecord: Equatable, Hashable {
    var name: String
    var command: String
    var isDefault: Bool

    init(name: String, command: String, isDefault: Bool = false) {
        self.name = name
        self.command = command
        self.isDefault = isDefault
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? command : trimmed
    }

    var normalizedCommand: String {
        command.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ProjectRecord: Equatable, Hashable {
    var path: String
    var name: String?
    var sections: [String]

    init(path: String, name: String? = nil, sections: [String] = []) {
        self.path = path
        self.name = name
        self.sections = sections
    }

    var displayName: String {
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }
}

struct ProjectSectionRecord: Equatable, Hashable {
    static let fallbackID = "other"

    var id: String
    var name: String?

    init(id: String, name: String? = nil) {
        self.id = id
        self.name = name
    }

    var displayName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed
        }
        return id
    }
}

struct CodeServerConfig: Equatable, Hashable {
    static let defaultPort = 8080

    var port: Int

    init(port: Int = CodeServerConfig.defaultPort) {
        self.port = CodeServerConfig.normalizedPort(port)
    }

    var resolvedPort: Int {
        CodeServerConfig.normalizedPort(port)
    }

    private static func normalizedPort(_ port: Int) -> Int {
        guard (1 ... 65535).contains(port) else {
            return defaultPort
        }
        return port
    }
}

enum ThemeToken: String, CaseIterable, Hashable, Codable {
    case background
    case backgroundSecondary
    case panel
    case panelRaised
    case panelMuted
    case border
    case borderStrong
    case foreground
    case foregroundMuted
    case foregroundDim
    case accent
    case accentForeground
    case selection
    case terminal
    case terminalForeground
    case success
    case warning
    case error
    case info
    case overlay
    case overlayStrong
    case shadow
}

struct ThemeColor: Equatable, Hashable, Codable {
    let hex: String

    init?(hex rawHex: String) {
        let trimmed = rawHex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ThemeColor.isSupportedHex(trimmed) else {
            return nil
        }
        hex = trimmed.uppercased()
    }

    var rgbHexWithoutHash: String {
        String(hex.dropFirst())
    }

    private static func isSupportedHex(_ value: String) -> Bool {
        let scalars = Array(value.unicodeScalars)
        guard scalars.count == 7 || scalars.count == 9 else {
            return false
        }
        guard scalars[0] == "#" else {
            return false
        }
        for scalar in scalars.dropFirst() {
            let character = scalar.value
            let isDigit = character >= 48 && character <= 57
            let isUpperHex = character >= 65 && character <= 70
            let isLowerHex = character >= 97 && character <= 102
            if !isDigit && !isUpperHex && !isLowerHex {
                return false
            }
        }
        return true
    }
}

struct ThemePalette: Equatable, Hashable {
    var colors: [ThemeToken: ThemeColor]

    init(colors: [ThemeToken: ThemeColor]) {
        self.colors = colors
    }

    init(defaultingTo defaults: ThemePalette, overrides: [ThemeToken: ThemeColor]) {
        colors = defaults.colors.merging(overrides) { _, override in
            override
        }
    }

    subscript(_ token: ThemeToken) -> ThemeColor {
        colors[token]!
    }

    var asHexMap: [String: String] {
        var map: [String: String] = [:]
        for token in ThemeToken.allCases {
            if let color = colors[token] {
                map[token.rawValue] = color.hex
            }
        }
        return map
    }
}

struct ThemeSet: Equatable, Hashable {
    var light: ThemePalette
    var dark: ThemePalette

    func palette(for mode: ThemeMode) -> ThemePalette {
        switch mode {
        case .dark:
            return dark
        case .light:
            return light
        }
    }

    static let `default` = ThemeSet(
        light: ThemePalette(
            colors: [
                .background: color("#F8FBFF"),
                .backgroundSecondary: color("#E9EEF6"),
                .panel: color("#FFFFFF"),
                .panelRaised: color("#EDF2F8"),
                .panelMuted: color("#E7EDF5"),
                .border: color("#D7E1EC"),
                .borderStrong: color("#B8C7D8"),
                .foreground: color("#152033"),
                .foregroundMuted: color("#5D6C80"),
                .foregroundDim: color("#8190A3"),
                .accent: color("#2B8AE6"),
                .accentForeground: color("#FFFFFF"),
                .selection: color("#DDEBFA"),
                .terminal: color("#E4EDF7"),
                .terminalForeground: color("#152033"),
                .success: color("#178A4C"),
                .warning: color("#AD6B00"),
                .error: color("#C64545"),
                .info: color("#1F78D1"),
                .overlay: color("#0000001F"),
                .overlayStrong: color("#00000085"),
                .shadow: color("#0000001F")
            ]
        ),
        dark: ThemePalette(
            colors: [
                .background: color("#0A0A0A"),
                .backgroundSecondary: color("#0A0A0A"),
                .panel: color("#181818"),
                .panelRaised: color("#202020"),
                .panelMuted: color("#121212"),
                .border: color("#262626"),
                .borderStrong: color("#303030"),
                .foreground: color("#F4F0EA"),
                .foregroundMuted: color("#A0A0A0"),
                .foregroundDim: color("#6E6E6E"),
                .accent: color("#C7771A"),
                .accentForeground: color("#0A0A0A"),
                .selection: color("#31240B"),
                .terminal: color("#161616"),
                .terminalForeground: color("#F4F0EA"),
                .success: color("#62E08B"),
                .warning: color("#FFC85C"),
                .error: color("#FF6B6B"),
                .info: color("#64C5FF"),
                .overlay: color("#00000057"),
                .overlayStrong: color("#00000085"),
                .shadow: color("#00000057")
            ]
        )
    )

    private static func color(_ hex: String) -> ThemeColor {
        ThemeColor(hex: hex)!
    }
}

struct SpurwechselConfig: Equatable {
    static let currentVersion = 1
    static let defaultAgents: [AgentConfigRecord] = [
        AgentConfigRecord(name: "opencode", command: "opencode", isDefault: true),
        AgentConfigRecord(name: "claude", command: "claude"),
        AgentConfigRecord(name: "codex", command: "codex")
    ]
    static let defaultShortcuts: [ShortcutRecord] = [
        ShortcutRecord(
            command: .toggleCommandBar,
            key: "k",
            modifiers: [.command]
        ),
        ShortcutRecord(
            command: .createDefaultAgent,
            key: "t",
            modifiers: [.command]
        ),
        ShortcutRecord(
            command: .selectNextAgent,
            key: "j",
            modifiers: [.command, .shift]
        ),
        ShortcutRecord(
            command: .selectPreviousAgent,
            key: "k",
            modifiers: [.command, .shift]
        ),
        ShortcutRecord(
            command: .selectProject,
            key: "p",
            modifiers: [.command]
        ),
        ShortcutRecord(
            command: .deleteAgent,
            key: "w",
            modifiers: [.command]
        ),
        ShortcutRecord(
            command: .togglePreviewPane,
            key: "s",
            modifiers: [.command, .shift]
        ),
        ShortcutRecord(
            command: .openAgentView,
            key: "u",
            modifiers: [.command, .shift]
        ),
        ShortcutRecord(
            command: .openTerminalView,
            key: "i",
            modifiers: [.command, .shift]
        ),
        ShortcutRecord(
            command: .openVSCodeView,
            key: "o",
            modifiers: [.command, .shift]
        )
    ]
    static let defaultTheme = ThemeSet.default

    var version: Int
    var codeServer: CodeServerConfig
    var sections: [ProjectSectionRecord]
    var projects: [ProjectRecord]
    var agents: [AgentConfigRecord]
    var shortcuts: [ShortcutRecord]
    var theme: ThemeSet

    init(
        version: Int = SpurwechselConfig.currentVersion,
        codeServer: CodeServerConfig = CodeServerConfig(),
        sections: [ProjectSectionRecord] = [],
        projects: [ProjectRecord] = [],
        agents: [AgentConfigRecord] = SpurwechselConfig.defaultAgents,
        shortcuts: [ShortcutRecord] = SpurwechselConfig.defaultShortcuts,
        theme: ThemeSet = SpurwechselConfig.defaultTheme
    ) {
        self.version = version
        self.codeServer = codeServer
        self.sections = sections
        self.projects = projects
        self.agents = agents
        self.shortcuts = shortcuts
        self.theme = theme
    }

    var resolvedAgents: [AgentConfigRecord] {
        let filtered = agents.filter { record in
            !record.displayName.isEmpty && !record.normalizedCommand.isEmpty
        }
        return filtered.isEmpty ? SpurwechselConfig.defaultAgents : filtered
    }

    var resolvedDefaultAgent: AgentConfigRecord {
        let agents = resolvedAgents
        if let flaggedDefault = agents.first(where: \.isDefault) {
            return flaggedDefault
        }
        return agents[0]
    }

    var resolvedShortcuts: [ResolvedShortcutBinding] {
        let fallbackByCommand = Dictionary(
            uniqueKeysWithValues: SpurwechselConfig.defaultShortcuts
                .compactMap { record in
                    ResolvedShortcutBinding(record: record).map { ($0.command, $0) }
                }
        )
        var explicitBindings: [ResolvedShortcutBinding] = []
        for record in shortcuts {
            guard let binding = ResolvedShortcutBinding(record: record) else {
                continue
            }
            explicitBindings.append(binding)
        }
        let explicitByCommand = Dictionary(
            uniqueKeysWithValues: explicitBindings.map { ($0.command, $0) }
        )
        let explicitSignatures = Set(explicitBindings.map(\.signature))

        func binding(for command: CommandID) -> ResolvedShortcutBinding? {
            if let explicitBinding = explicitByCommand[command] {
                return explicitBinding
            }
            guard let fallbackBinding = fallbackByCommand[command],
                  !explicitSignatures.contains(fallbackBinding.signature) else {
                return nil
            }
            return fallbackBinding
        }

        var consumedSignatures = Set<String>()
        var resolved: [ResolvedShortcutBinding] = []
        for command in CommandID.allCases {
            guard let binding = binding(for: command) else {
                continue
            }
            guard !consumedSignatures.contains(binding.signature) else {
                continue
            }
            consumedSignatures.insert(binding.signature)
            resolved.append(binding)
        }

        return resolved
    }

    func shortcutBinding(for command: CommandID) -> ResolvedShortcutBinding? {
        resolvedShortcuts.first(where: { $0.command == command })
    }
}

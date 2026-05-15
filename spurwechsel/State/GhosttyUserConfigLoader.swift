import Foundation
import GhosttyTerminal

struct ImportedGhosttyTerminalConfig: Equatable {
    var terminalConfiguration: TerminalConfiguration
    var surfaceFontSize: Float?

    static let empty = ImportedGhosttyTerminalConfig(
        terminalConfiguration: .init(),
        surfaceFontSize: nil
    )
}

struct GhosttyUserConfigLoader {
    private let fileManager: FileManager
    private let environment: [String: String]
    private let homeDirectoryPath: String

    init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectoryPath: String = NSHomeDirectory()
    ) {
        self.fileManager = fileManager
        self.environment = environment
        self.homeDirectoryPath = homeDirectoryPath
    }

    func load() -> ImportedGhosttyTerminalConfig {
        var parsed = ParsedGhosttyConfig()
        var visited = Set<String>()
        for path in defaultConfigPaths() {
            parseConfigFile(
                at: URL(fileURLWithPath: path),
                parsed: &parsed,
                visited: &visited
            )
        }
        return parsed.rendered
    }
}

private extension GhosttyUserConfigLoader {
    struct ParsedLine {
        var key: String
        var value: String
        var valueWasQuoted: Bool
    }

    enum CopyOnSelectValue: String {
        case trueValue = "true"
        case falseValue = "false"
        case clipboard
    }

    struct ParsedGhosttyConfig {
        var fontFamilies: [String] = []
        var fontSize: Float?
        var fontThicken: Bool?
        var fontThickenStrength: Int?
        var cursorStyle: TerminalCursorStyle?
        var cursorStyleBlink: Bool?
        var cursorOpacity: Double?
        var selectionClearOnCopy: Bool?
        var selectionClearOnTyping: Bool?
        var selectionWordChars: String?
        var mouseHideWhileTyping: Bool?
        var mouseScrollMultiplier: String?
        var copyOnSelect: CopyOnSelectValue?
        var scrollbackLimit: Int?

        var rendered: ImportedGhosttyTerminalConfig {
            var configuration = TerminalConfiguration()

            for family in fontFamilies {
                configuration = configuration.fontFamily(family)
            }
            if let fontSize {
                configuration = configuration.fontSize(fontSize)
            }
            if let fontThicken {
                configuration = configuration.fontThicken(fontThicken)
            }
            if let fontThickenStrength {
                configuration = configuration.fontThickenStrength(fontThickenStrength)
            }
            if let cursorStyle {
                configuration = configuration.cursorStyle(cursorStyle)
            }
            if let cursorStyleBlink {
                configuration = configuration.cursorStyleBlink(cursorStyleBlink)
            }
            if let cursorOpacity {
                configuration = configuration.cursorOpacity(cursorOpacity)
            }
            if let selectionClearOnCopy {
                configuration = configuration.custom(
                    "selection-clear-on-copy",
                    selectionClearOnCopy ? "true" : "false"
                )
            }
            if let selectionClearOnTyping {
                configuration = configuration.custom(
                    "selection-clear-on-typing",
                    selectionClearOnTyping ? "true" : "false"
                )
            }
            if let selectionWordChars {
                configuration = configuration.custom("selection-word-chars", selectionWordChars)
            }
            if let mouseHideWhileTyping {
                configuration = configuration.custom(
                    "mouse-hide-while-typing",
                    mouseHideWhileTyping ? "true" : "false"
                )
            }
            if let mouseScrollMultiplier {
                configuration = configuration.custom("mouse-scroll-multiplier", mouseScrollMultiplier)
            }
            if let copyOnSelect {
                configuration = configuration.custom("copy-on-select", copyOnSelect.rawValue)
            }
            if let scrollbackLimit {
                configuration = configuration.custom("scrollback-limit", String(scrollbackLimit))
            }

            return ImportedGhosttyTerminalConfig(
                terminalConfiguration: configuration,
                surfaceFontSize: fontSize
            )
        }
    }

    func defaultConfigPaths() -> [String] {
        let xdgHome = environment["XDG_CONFIG_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedXDGHome: String
        if let xdgHome, !xdgHome.isEmpty {
            resolvedXDGHome = xdgHome
        } else {
            resolvedXDGHome = URL(fileURLWithPath: homeDirectoryPath)
                .appendingPathComponent(".config", isDirectory: true)
                .path
        }

        let xdgBase = URL(fileURLWithPath: resolvedXDGHome)
            .appendingPathComponent("ghostty", isDirectory: true)
        let macBase = URL(fileURLWithPath: homeDirectoryPath)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("com.mitchellh.ghostty", isDirectory: true)

        return [
            xdgBase.appendingPathComponent("config.ghostty").path,
            xdgBase.appendingPathComponent("config").path,
            macBase.appendingPathComponent("config.ghostty").path,
            macBase.appendingPathComponent("config").path
        ]
    }

    func parseConfigFile(
        at url: URL,
        parsed: inout ParsedGhosttyConfig,
        visited: inout Set<String>
    ) {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        let canonicalPath = canonicalPathForLoadedFile(url)
        guard visited.insert(canonicalPath).inserted else {
            return
        }

        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return
        }

        var includes: [ParsedLine] = []
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            guard let parsedLine = parseLine(String(rawLine)) else {
                continue
            }
            if parsedLine.key == "config-file" {
                includes.append(parsedLine)
            } else {
                applyParsedLine(parsedLine, to: &parsed)
            }
        }

        for include in includes {
            guard let includeTarget = resolveIncludeTarget(
                include,
                parentURL: url
            ) else {
                continue
            }
            parseConfigFile(
                at: includeTarget,
                parsed: &parsed,
                visited: &visited
            )
        }
    }

    func canonicalPathForLoadedFile(_ url: URL) -> String {
        let standardized = url.standardizedFileURL
        if fileManager.fileExists(atPath: standardized.path) {
            return standardized.resolvingSymlinksInPath().path
        }
        return standardized.path
    }

    func parseLine(_ rawLine: String) -> ParsedLine? {
        let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
            return nil
        }

        guard let equalsIndex = trimmed.firstIndex(of: "=") else {
            return nil
        }

        let key = trimmed[..<equalsIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            return nil
        }

        let rawValueStart = trimmed.index(after: equalsIndex)
        let rawValue = String(trimmed[rawValueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let (value, wasQuoted) = unquote(rawValue)
        return ParsedLine(key: key, value: value, valueWasQuoted: wasQuoted)
    }

    func unquote(_ rawValue: String) -> (String, Bool) {
        guard rawValue.count >= 2,
              rawValue.hasPrefix("\""),
              rawValue.hasSuffix("\"")
        else {
            return (rawValue, false)
        }

        var payload = String(rawValue.dropFirst().dropLast())
        payload = payload.replacingOccurrences(of: "\\\"", with: "\"")
        payload = payload.replacingOccurrences(of: "\\\\", with: "\\")
        return (payload, true)
    }

    func resolveIncludeTarget(
        _ include: ParsedLine,
        parentURL: URL
    ) -> URL? {
        var includePath = include.value
        var isOptional = false

        if !include.valueWasQuoted, includePath.hasPrefix("?") {
            isOptional = true
            includePath.removeFirst()
        }

        let trimmed = includePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let includeURL: URL
        if trimmed.hasPrefix("/") {
            includeURL = URL(fileURLWithPath: trimmed)
        } else {
            includeURL = parentURL
                .deletingLastPathComponent()
                .appendingPathComponent(trimmed)
        }

        if fileManager.fileExists(atPath: includeURL.path) {
            return includeURL
        }

        return isOptional ? nil : includeURL
    }

    func applyParsedLine(
        _ line: ParsedLine,
        to parsed: inout ParsedGhosttyConfig
    ) {
        switch line.key {
        case "font-family":
            if line.value.isEmpty {
                parsed.fontFamilies.removeAll()
                return
            }
            parsed.fontFamilies.append(line.value)

        case "font-size":
            if line.value.isEmpty {
                parsed.fontSize = nil
                return
            }
            guard let value = Float(line.value), value > 0 else {
                return
            }
            parsed.fontSize = value

        case "font-thicken":
            if line.value.isEmpty {
                parsed.fontThicken = nil
                return
            }
            guard let value = parseBoolean(line.value) else {
                return
            }
            parsed.fontThicken = value

        case "font-thicken-strength":
            if line.value.isEmpty {
                parsed.fontThickenStrength = nil
                return
            }
            guard let value = Int(line.value), (0 ... 255).contains(value) else {
                return
            }
            parsed.fontThickenStrength = value

        case "cursor-style":
            if line.value.isEmpty {
                parsed.cursorStyle = nil
                return
            }
            guard let style = TerminalCursorStyle(rawValue: line.value.lowercased()) else {
                return
            }
            parsed.cursorStyle = style

        case "cursor-style-blink":
            if line.value.isEmpty {
                parsed.cursorStyleBlink = nil
                return
            }
            guard let value = parseBoolean(line.value) else {
                return
            }
            parsed.cursorStyleBlink = value

        case "cursor-opacity":
            if line.value.isEmpty {
                parsed.cursorOpacity = nil
                return
            }
            guard let value = Double(line.value), (0 ... 1).contains(value) else {
                return
            }
            parsed.cursorOpacity = value

        case "selection-clear-on-copy":
            if line.value.isEmpty {
                parsed.selectionClearOnCopy = nil
                return
            }
            guard let value = parseBoolean(line.value) else {
                return
            }
            parsed.selectionClearOnCopy = value

        case "selection-clear-on-typing":
            if line.value.isEmpty {
                parsed.selectionClearOnTyping = nil
                return
            }
            guard let value = parseBoolean(line.value) else {
                return
            }
            parsed.selectionClearOnTyping = value

        case "selection-word-chars":
            parsed.selectionWordChars = line.value.isEmpty ? nil : line.value

        case "mouse-hide-while-typing":
            if line.value.isEmpty {
                parsed.mouseHideWhileTyping = nil
                return
            }
            guard let value = parseBoolean(line.value) else {
                return
            }
            parsed.mouseHideWhileTyping = value

        case "mouse-scroll-multiplier":
            if line.value.isEmpty {
                parsed.mouseScrollMultiplier = nil
                return
            }
            guard sanitizeMouseScrollMultiplier(line.value) != nil else {
                return
            }
            parsed.mouseScrollMultiplier = line.value

        case "copy-on-select":
            if line.value.isEmpty {
                parsed.copyOnSelect = nil
                return
            }
            let normalized = line.value.lowercased()
            guard let value = CopyOnSelectValue(rawValue: normalized) else {
                return
            }
            parsed.copyOnSelect = value

        case "scrollback-limit":
            if line.value.isEmpty {
                parsed.scrollbackLimit = nil
                return
            }
            guard let value = Int(line.value), value >= 0 else {
                return
            }
            parsed.scrollbackLimit = value

        default:
            break
        }
    }

    func parseBoolean(_ rawValue: String) -> Bool? {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "true":
            return true
        case "false":
            return false
        default:
            return nil
        }
    }

    func sanitizeMouseScrollMultiplier(_ rawValue: String) -> String? {
        let components = rawValue
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !components.isEmpty else {
            return nil
        }

        for component in components {
            if component.contains(":") {
                let pair = component.split(separator: ":", maxSplits: 1).map(String.init)
                guard pair.count == 2 else {
                    return nil
                }
                let prefix = pair[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard prefix == "precision" || prefix == "discrete" else {
                    return nil
                }
                guard let value = Double(pair[1].trimmingCharacters(in: .whitespacesAndNewlines)),
                      value > 0 else {
                    return nil
                }
            } else {
                guard let value = Double(component), value > 0 else {
                    return nil
                }
            }
        }

        return rawValue
    }
}

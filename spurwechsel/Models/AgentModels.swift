import Foundation

enum AgentKind: String, Hashable {
    case opencode
    case unknown

    static func detect(from launchCommand: String) -> AgentKind {
        guard let token = firstCommandToken(in: launchCommand)?.lowercased() else {
            return .unknown
        }

        switch token {
        case "opencode":
            return .opencode
        default:
            return .unknown
        }
    }

    private static func firstCommandToken(in command: String) -> String? {
        for token in command.split(whereSeparator: \.isWhitespace) {
            let tokenString = String(token)
            if isEnvironmentAssignment(tokenString) {
                continue
            }
            return tokenString
        }
        return nil
    }

    private static func isEnvironmentAssignment(_ token: String) -> Bool {
        guard let equalsIndex = token.firstIndex(of: "="), equalsIndex != token.startIndex else {
            return false
        }

        let key = token[..<equalsIndex]
        for (index, character) in key.enumerated() {
            if index == 0 {
                guard character == "_" || character.isASCIIUppercaseLetter || character.isASCIILowercaseLetter else {
                    return false
                }
            } else {
                guard character == "_" || character.isASCIIUppercaseLetter || character.isASCIILowercaseLetter || character.isNumber else {
                    return false
                }
            }
        }
        return true
    }
}

enum AgentRichStatusEventType: String, Decodable, Hashable {
    case sessionStart = "session_start"
    case promptSubmit = "prompt_submit"
    case toolComplete = "tool_complete"
    case stop
    case permissionRequest = "permission_request"
    case permissionReplied = "permission_replied"
    case questionAsked = "question_asked"
    case idlePrompt = "idle_prompt"
}

struct AgentRichStatusEvent: Decodable, Hashable {
    static let notificationTitle = "warp://cli-agent"

    let agent: AgentKind
    let type: AgentRichStatusEventType
    let summary: String?
    let pluginVersion: String?

    private enum CodingKeys: String, CodingKey {
        case agent
        case type = "event"
        case summary
        case pluginVersion = "plugin_version"
    }

    private enum ParseError: LocalizedError {
        case missingField(String)
        case invalidEventType(String)
        case invalidJSONString(String)

        var errorDescription: String? {
            switch self {
            case let .missingField(field):
                return "Missing field '\(field)'"
            case let .invalidEventType(value):
                return "Unsupported event '\(value)'"
            case let .invalidJSONString(field):
                return "Invalid JSON string encoding for '\(field)'"
            }
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawAgent = try container.decode(String.self, forKey: .agent)
        agent = AgentKind.detect(from: rawAgent)
        type = try container.decode(AgentRichStatusEventType.self, forKey: .type)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        pluginVersion = try container.decodeIfPresent(String.self, forKey: .pluginVersion)
    }

    enum ParseOutcome: Hashable {
        case wrongTitle
        case invalidPayload(String?)
        case parsed(AgentRichStatusEvent)
    }

    static func parseDesktopNotification(title: String, body: String) -> ParseOutcome {
        guard title == notificationTitle else {
            return .wrongTitle
        }
        switch decodeEvent(from: body) {
        case let .success(event):
            return .parsed(event)
        case let .failure(error):
            return .invalidPayload(error.localizedDescription)
        }
    }

    private static func decodeEvent(from body: String) -> Result<AgentRichStatusEvent, Error> {
        let candidate = extractedJSONObjectCandidate(from: body)
        var strictFailure: Error?

        do {
            let event = try JSONDecoder().decode(AgentRichStatusEvent.self, from: Data(candidate.utf8))
            return .success(event)
        } catch {
            strictFailure = error
            if case let .success(event) = decodeEventStrict(candidate) {
                return .success(event)
            }
        }

        if case let .success(event) = decodeEventLenient(candidate) {
            return .success(event)
        }
        return .failure(strictFailure ?? ParseError.invalidJSONString("payload"))
    }

    private static func decodeEventStrict(_ value: String) -> Result<AgentRichStatusEvent, Error> {
        Result {
            try JSONDecoder().decode(AgentRichStatusEvent.self, from: Data(value.utf8))
        }
    }

    private static func decodeEventLenient(_ value: String) -> Result<AgentRichStatusEvent, Error> {
        do {
            guard let rawAgent = extractJSONStringValue(forKey: "agent", in: value) else {
                throw ParseError.missingField("agent")
            }
            guard let rawEvent = extractJSONStringValue(forKey: "event", in: value) else {
                throw ParseError.missingField("event")
            }
            guard let type = AgentRichStatusEventType(rawValue: rawEvent) else {
                throw ParseError.invalidEventType(rawEvent)
            }
            let summary = extractJSONStringValue(forKey: "summary", in: value)
            let pluginVersion = extractJSONStringValue(forKey: "plugin_version", in: value)
            return .success(
                AgentRichStatusEvent(
                    agent: AgentKind.detect(from: rawAgent),
                    type: type,
                    summary: summary,
                    pluginVersion: pluginVersion
                )
            )
        } catch {
            return .failure(error)
        }
    }

    private static func extractedJSONObjectCandidate(from body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstBrace = trimmed.firstIndex(of: "{"),
              let lastBrace = trimmed.lastIndex(of: "}"),
              firstBrace <= lastBrace else {
            return trimmed
        }
        return String(trimmed[firstBrace...lastBrace]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractJSONStringValue(forKey key: String, in payload: String) -> String? {
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        let pattern = #""\#(escapedKey)"\s*:\s*"((?:\\.|[^"\\])*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(payload.startIndex..<payload.endIndex, in: payload)
        guard let match = regex.firstMatch(in: payload, range: range),
              match.numberOfRanges > 1,
              let encodedRange = Range(match.range(at: 1), in: payload) else {
            return nil
        }

        let encoded = String(payload[encodedRange])
        let wrapped = "\"\(encoded)\""
        guard let data = wrapped.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(String.self, from: data) else {
            return nil
        }
        return decoded
    }

    private init(
        agent: AgentKind,
        type: AgentRichStatusEventType,
        summary: String?,
        pluginVersion: String?
    ) {
        self.agent = agent
        self.type = type
        self.summary = summary
        self.pluginVersion = pluginVersion
    }
}

enum AgentSessionStatus: String, CaseIterable, Hashable {
    case launching
    case idle
    case running
    case waitingApproval
    case waitingInput
    case exited
    case failed

    var title: String {
        switch self {
        case .launching:
            return "Launching"
        case .idle:
            return "Idle"
        case .running:
            return "Running"
        case .waitingApproval:
            return "Waiting Approval"
        case .waitingInput:
            return "Waiting Input"
        case .exited:
            return "Exited"
        case .failed:
            return "Failed"
        }
    }

    var symbolName: String {
        switch self {
        case .launching:
            return "arrow.triangle.2.circlepath"
        case .idle:
            return "pause.circle"
        case .running:
            return "bolt.circle"
        case .waitingApproval:
            return "checkmark.shield"
        case .waitingInput:
            return "text.bubble"
        case .exited:
            return "stop.circle"
        case .failed:
            return "xmark.octagon"
        }
    }
}

enum TranscriptEntryRole: Hashable {
    case note
    case command
    case assistant
    case output
}

struct TranscriptEntry: Identifiable, Equatable, Hashable {
    let id: UUID
    let role: TranscriptEntryRole
    let text: String

    init(id: UUID = UUID(), role: TranscriptEntryRole, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

struct AgentSession: Identifiable, Equatable, Hashable {
    let id: UUID
    var workspaceSelection: WorkspaceSelection
    var name: String
    var kind: AgentKind
    var status: AgentSessionStatus
    var statusDetail: String?
    var launcherName: String
    var launchCommand: String
    var workingDirectory: String
    var terminalTitle: String
    var lastActivity: String
    var exitCode: Int32?
    var pluginVersion: String?
    var expectsRichStatus: Bool
    var hasRichStatus: Bool
    var showsWarpPluginWarning: Bool {
        kind == .opencode && !expectsRichStatus
    }

    init(
        id: UUID = UUID(),
        workspaceSelection: WorkspaceSelection,
        name: String,
        kind: AgentKind = .unknown,
        status: AgentSessionStatus,
        statusDetail: String? = nil,
        launcherName: String,
        launchCommand: String,
        workingDirectory: String,
        terminalTitle: String,
        lastActivity: String,
        exitCode: Int32?,
        pluginVersion: String? = nil,
        expectsRichStatus: Bool = false,
        hasRichStatus: Bool = false
    ) {
        self.id = id
        self.workspaceSelection = workspaceSelection
        self.name = name
        self.kind = kind
        self.status = status
        self.statusDetail = statusDetail
        self.launcherName = launcherName
        self.launchCommand = launchCommand
        self.workingDirectory = workingDirectory
        self.terminalTitle = terminalTitle
        self.lastActivity = lastActivity
        self.exitCode = exitCode
        self.pluginVersion = pluginVersion
        self.expectsRichStatus = expectsRichStatus
        self.hasRichStatus = hasRichStatus
    }
}

private extension Character {
    var isASCIIUppercaseLetter: Bool {
        ("A"..."Z").contains(self)
    }

    var isASCIILowercaseLetter: Bool {
        ("a"..."z").contains(self)
    }
}

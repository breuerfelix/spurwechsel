import Foundation

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
    var status: AgentSessionStatus
    var launcherName: String
    var launchCommand: String
    var workingDirectory: String
    var terminalTitle: String
    var lastActivity: String
    var exitCode: Int32?

    init(
        id: UUID = UUID(),
        workspaceSelection: WorkspaceSelection,
        name: String,
        status: AgentSessionStatus,
        launcherName: String,
        launchCommand: String,
        workingDirectory: String,
        terminalTitle: String,
        lastActivity: String,
        exitCode: Int32?
    ) {
        self.id = id
        self.workspaceSelection = workspaceSelection
        self.name = name
        self.status = status
        self.launcherName = launcherName
        self.launchCommand = launchCommand
        self.workingDirectory = workingDirectory
        self.terminalTitle = terminalTitle
        self.lastActivity = lastActivity
        self.exitCode = exitCode
    }
}

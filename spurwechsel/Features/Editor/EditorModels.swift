import Foundation

enum VSCodeServerStatus: Hashable {
    case idle
    case missingWorkspace
    case starting
    case running
    case authRequired
    case stopping
    case stopped
    case cliMissing
    case portInUse
    case startupFailed
    case urlNotFound
}

enum VSCodeBrowserPhase: Equatable {
    case idle
    case loading
    case ready
    case failed(String)
}

struct VSCodeServerState: Equatable {
    var workspaceSelectionID: String?
    var workspaceName: String?
    var workspacePath: String?
    var serverAddress: String?
    var workspaceAddress: String?
    var status: VSCodeServerStatus = .idle
    var statusMessage = "Select VSCode view to start code-server."
    var errorMessage: String?
    var lastOutputLine: String?
    var browserPhase: VSCodeBrowserPhase = .idle
}

typealias EditorSessionState = VSCodeServerState

struct TerminalSessionState: Equatable {
    var workspaceSelectionID: String
    var isAttached = false
}

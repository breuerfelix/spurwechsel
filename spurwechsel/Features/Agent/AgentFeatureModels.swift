import Foundation

struct AgentState: Equatable {
    var sessions: [AgentSession]
    var selectedSessionID: UUID?
    var nextAgentCount: Int

    var selectedSession: AgentSession? {
        guard let selectedSessionID else {
            return nil
        }

        return sessions.first { $0.id == selectedSessionID }
    }

    mutating func selectSession(_ sessionID: UUID) {
        selectedSessionID = sessionID
    }

    func sessions(for selection: WorkspaceSelection) -> [AgentSession] {
        sessions.filter { $0.workspaceSelection == selection }
    }

    func firstSession(in selection: WorkspaceSelection) -> AgentSession? {
        sessions(for: selection).first
    }

    mutating func addAgent(
        to selection: WorkspaceSelection,
        launcherName: String,
        launchCommand: String,
        workingDirectory: String,
        kind: AgentKind = .unknown,
        expectsRichStatus: Bool = false
    ) -> AgentSession {
        let session = AgentSession(
            workspaceSelection: selection,
            name: "\(launcherName)-\(nextAgentCount)",
            kind: kind,
            status: .launching,
            launcherName: launcherName,
            launchCommand: launchCommand,
            workingDirectory: workingDirectory,
            terminalTitle: launcherName,
            lastActivity: "now",
            exitCode: nil,
            expectsRichStatus: expectsRichStatus
        )
        nextAgentCount += 1
        sessions.append(session)
        selectedSessionID = session.id
        return session
    }

    mutating func updateStatus(
        for sessionID: UUID,
        status: AgentSessionStatus,
        detail: String? = nil
    ) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }
        sessions[index].status = status
        sessions[index].statusDetail = detail
    }

    mutating func updateRichStatusMetadata(
        for sessionID: UUID,
        pluginVersion: String?
    ) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }
        sessions[index].hasRichStatus = true
        if let pluginVersion {
            sessions[index].pluginVersion = pluginVersion
        }
    }

    mutating func updateTerminalTitle(for sessionID: UUID, title: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }
        sessions[index].terminalTitle = title
        let resolvedName = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !resolvedName.isEmpty {
            sessions[index].name = resolvedName
        }
    }

    mutating func updateExitCode(for sessionID: UUID, exitCode: Int32?) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }
        sessions[index].exitCode = exitCode
        sessions[index].lastActivity = "just now"
    }

    mutating func markRuntimeReady(for sessionID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }
        sessions[index].runtimeReady = true
    }

    mutating func removeSession(_ sessionID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }
        let removedSession = sessions[index]
        sessions.remove(at: index)

        if selectedSessionID == sessionID {
            let fallback = sessions.first { $0.workspaceSelection == removedSession.workspaceSelection }
            selectedSessionID = fallback?.id
        }
    }

    mutating func removeSessions(in selections: Set<WorkspaceSelection>) -> [UUID] {
        guard !selections.isEmpty else {
            return []
        }

        let removedSessions = sessions.filter { selections.contains($0.workspaceSelection) }
        guard !removedSessions.isEmpty else {
            return []
        }

        let removedSessionIDs = Set(removedSessions.map(\.id))
        sessions.removeAll { removedSessionIDs.contains($0.id) }

        if let selectedSessionID,
           !sessions.contains(where: { $0.id == selectedSessionID }) {
            self.selectedSessionID = nil
        }
        if selectedSessionID == nil {
            selectedSessionID = sessions.first?.id
        }

        return removedSessions.map(\.id)
    }
}

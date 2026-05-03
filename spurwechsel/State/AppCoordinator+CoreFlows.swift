import AppKit
import Foundation
import GhosttyTerminal
import os
import SwiftUI

enum CommandInvocationSource {
    case commandBar
    case shortcut
    case direct
}

@MainActor
extension AppCoordinator {
    func requestApplicationQuit() {
        store.applicationQuitHandler()
    }

    func shutdownTerminalRuntimes() {
        Task {
            _ = await prepareForTermination()
        }
    }

    func dismissConfigNotification() {
        shellStore.dismissConfigNotification()
    }

    func prepareForTermination() async -> AppTerminationSummary {
        if let inFlightAppShutdownTask {
            return await inFlightAppShutdownTask.value
        }

        shellStore.beginShutdown()

        let shutdownTask = Task { [weak self] in
            guard let self else {
                return AppTerminationSummary(forcedKillCount: 0, timedOutCount: 0)
            }

            async let terminalSummary = self.terminalRegistry.shutdownAll(
                graceTimeout: Self.shutdownGraceTimeout,
                forceKillTimeout: Self.shutdownForceKillTimeout
            )
            async let serverSummary = self.vscodeServerRuntime.shutdown(
                graceTimeout: Self.shutdownGraceTimeout,
                forceKillTimeout: Self.shutdownForceKillTimeout
            )
            let (terminalSummaryValue, serverSummaryValue) = await (terminalSummary, serverSummary)

            let forcedKillCount = terminalSummaryValue.forcedKillCount + (serverSummaryValue.didForceKill ? 1 : 0)
            let timedOutCount = terminalSummaryValue.timedOutCount + (serverSummaryValue.didTimeout ? 1 : 0)

            await MainActor.run {
                if timedOutCount > 0 {
                    self.shellStore.setShutdownProgress(
                        status: "Forcing final shutdown…",
                        detail: "Force-closed \(forcedKillCount) session(s). \(timedOutCount) did not confirm exit."
                    )
                    Self.logger.error(
                        "App shutdown finished with unresolved process exits: forced=\(forcedKillCount, privacy: .public) unresolved=\(timedOutCount, privacy: .public)"
                    )
                } else if forcedKillCount > 0 {
                    self.shellStore.setShutdownProgress(
                        status: "Finalizing shutdown…",
                        detail: "Force-closed \(forcedKillCount) unresponsive session(s)."
                    )
                    Self.logger.notice(
                        "App shutdown used force-kill path for \(forcedKillCount, privacy: .public) session(s)."
                    )
                } else {
                    self.shellStore.setShutdownProgress(
                        status: "Finalizing shutdown…",
                        detail: "All managed sessions closed cleanly."
                    )
                }
            }

            return AppTerminationSummary(
                forcedKillCount: forcedKillCount,
                timedOutCount: timedOutCount
            )
        }

        inFlightAppShutdownTask = shutdownTask
        let summary = await shutdownTask.value
        inFlightAppShutdownTask = nil
        return summary
    }

    func setApplicationActive(_ isActive: Bool) {
        guard shellStore.appIsActive != isActive else {
            return
        }
        shellStore.setApplicationActive(isActive)
        syncTerminalSurfaceActivation()
    }

    func setWindowKey(_ isKey: Bool) {
        guard shellStore.windowIsKey != isKey else {
            return
        }
        shellStore.setWindowKey(isKey)
        syncTerminalSurfaceActivation()
    }

    func recordFocusedSurfaceSlot(_ slot: SurfaceSlot) {
        layout.rememberFocusedSlot(slot)
    }

    var theme: SpurTheme { projectConfig.theme.spurTheme(for: layout.themeMode) }
    var terminalTheme: TerminalTheme { projectConfig.theme.terminalTheme }

    var terminalSurfacesAreForeground: Bool {
        appIsActive && windowIsKey
    }

    var mountedMainSurfaceID: SurfaceTabID? {
        surfaceMountState.mainSurfaceID
    }

    var mountedPreviewSurfaceID: SurfaceTabID? {
        surfaceMountState.previewSurfaceID
    }

    var selectedWorkspace: WorkspaceSelection {
        projects.selection
    }

    var selectedWorkspaceNode: WorkspaceNode? {
        projects.node(for: projects.selection)
    }

    var groupedAgentNodes: [(WorkspaceNode, [AgentSession])] {
        projects.orderedNodes.map { node in
            (node, agents.sessions(for: node.selection))
        }
    }

    var selectedAgent: AgentSession? {
        if let selectedTabID = surfaceTabs.selectedTabID,
           case let .agentSession(sessionID) = selectedTabID,
           let session = agents.sessions.first(where: { $0.id == sessionID }) {
            return session
        }

        if let selectedSession = agents.selectedSession {
            return selectedSession
        }

        return agents.firstSession(in: projects.selection)
    }

    func resolvedAgentSession(
        sessionID: UUID?,
        in workspaceSelection: WorkspaceSelection
    ) -> AgentSession? {
        if let sessionID {
            return agents.sessions.first(where: { $0.id == sessionID })
        }

        if let selectedSession = agents.selectedSession,
           selectedSession.workspaceSelection == workspaceSelection {
            return selectedSession
        }

        return agents.firstSession(in: workspaceSelection)
    }

    func terminalController(for sessionID: UUID) -> AgentTerminalSessionController? {
        terminalRegistry.controller(for: .agent(sessionID))
    }

    func surfaceTab(for id: SurfaceTabID) -> SurfaceTab? {
        surfaceTabs.tabs.first(where: { $0.id == id })
    }

    func projectTerminalController(
        for selection: WorkspaceSelection? = nil
    ) -> LocalShellTerminalSessionController? {
        let resolvedSelection = selection ?? projects.selection
        guard let workingDirectory = projects.path(for: resolvedSelection) else {
            return nil
        }
        return terminalRegistry.acquire(id: .workspace(resolvedSelection.stableID)) {
            let launchPlan = LocalShellTerminalSessionController.makeDefaultShellLaunchPlan(
                workingDirectory: workingDirectory
            )
            return LocalShellTerminalSessionController(
                sessionID: UUID(),
                startupTitle: "terminal",
                launchPlan: launchPlan,
                terminalTheme: terminalTheme,
                onTitleChange: { _ in },
                onProcessTerminated: { _ in }
            )
        }
    }

    func vscodeWebRuntime(forWorkspaceID workspaceID: String) -> EmbeddedWebViewRuntime? {
        vscodeWebRuntimesByWorkspaceID[workspaceID]
    }

    func editorSession(for workspaceID: String) -> EditorSessionState? {
        editorSessionsByWorkspaceID[workspaceID]
    }

    var configuredAgents: [AgentConfigRecord] {
        projectConfig.resolvedAgents
    }

    var configuredDefaultAgent: AgentConfigRecord {
        projectConfig.resolvedDefaultAgent
    }

    var configuredShortcuts: [ResolvedShortcutBinding] {
        projectConfig.resolvedShortcuts
    }

    func shortcutBinding(for command: CommandID) -> ResolvedShortcutBinding? {
        projectConfig.shortcutBinding(for: command)
    }

    @discardableResult
    func handleGlobalShortcutEvent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else {
            return false
        }
        guard let eventKey = Self.normalizedShortcutKey(from: event) else {
            return false
        }
        let eventModifiers = Self.shortcutModifiers(from: event)

        guard let matchedBinding = configuredShortcuts.first(where: {
            $0.key == eventKey && $0.modifiers == eventModifiers
        }) else {
            return false
        }

        dispatchShortcutCommand(matchedBinding.command)
        return true
    }

    func dispatchShortcutCommand(_ command: CommandID) {
        executeCommand(command, source: .shortcut)
    }

    var filteredCommands: [CommandID] {
        guard case .commandList = commandBar.mode else {
            return []
        }

        let trimmedQuery = commandBar.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let commands = CommandID.allCases

        guard !trimmedQuery.isEmpty else {
            return commands
        }

        let scored = commands.enumerated().compactMap { index, command -> (CommandID, Int, Int)? in
            let candidateStrings = [command.title] + command.keywords
            let bestScore = candidateStrings.compactMap {
                Self.fuzzyScore(query: trimmedQuery, candidate: $0)
            }.min()
            guard let bestScore else {
                return nil
            }
            return (command, bestScore, index)
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.2 < rhs.2
                }
                return lhs.1 < rhs.1
            }
            .map(\.0)
    }

    var filteredPickerItems: [CommandBarPickerItem] {
        guard case let .picker(_, items, _) = commandBar.mode else {
            return []
        }

        let trimmedQuery = commandBar.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return items
        }

        let scored = items.enumerated().compactMap { index, item -> (CommandBarPickerItem, Int, Int)? in
            let candidateStrings = [item.title, item.subtitle]
            let bestScore = candidateStrings.compactMap {
                Self.fuzzyScore(query: trimmedQuery, candidate: $0)
            }.min()
            guard let bestScore else {
                return nil
            }
            return (item, bestScore, index)
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.2 < rhs.2
                }
                return lhs.1 < rhs.1
            }
            .map(\.0)
    }

    func toggleLeftSidebar() {
        layout.toggleLeftSidebar()
    }

    func toggleRightSidebar() {
        layout.toggleRightSidebar()
    }

    func togglePreview() {
        layout.togglePreview()
        syncMountedSurfaces()
        if layout.previewEnabled {
            requestSurfaceFocus(.preview)
        } else {
            requestSurfaceFocus(.main)
        }
        syncTerminalSurfaceActivation()
    }

    func setPreferredPreviewWidth(
        _ width: CGFloat,
        allowedRange: ClosedRange<CGFloat>
    ) {
        layout.setPreferredPreviewWidth(width, allowedRange: allowedRange)
    }

    func toggleTheme() {
        layout.toggleTheme()
    }

    func selectMainView(_ view: MainViewKind) {
        switch view {
        case .agent:
            selectOrCreateAgentTab(for: projects.selection)
        case .terminal:
            selectOrCreateWorkspaceTerminalTab(for: projects.selection)
        case .vscode:
            selectOrCreateVSCodeTab(for: projects.selection)
        }
        syncMountedSurfaces()
        requestSurfaceFocus(preferredSurfaceSlotForCurrentMainView())
        syncTerminalSurfaceActivation()
    }

    func selectPreviewView(_ view: PreviewViewKind) {
        layout.selectPreviewView(view)
        syncMountedSurfaces()
        if view == .vscode, layout.previewEnabled {
            ensureVSCodeServerForSelectedWorkspace(forceRestart: false)
        }
        requestSurfaceFocus(.preview)
        syncTerminalSurfaceActivation()
    }

    func selectWorkspace(_ selection: WorkspaceSelection) {
        Self.logger.debug("Workspace switch requested: \(selection.stableID, privacy: .public)")
        projects.select(selection)
        if layout.selectedMainView == .terminal {
            _ = projectTerminalController(for: selection)
        } else if layout.selectedMainView == .vscode {
            ensureVSCodeServerForSelectedWorkspace(forceRestart: false)
        }
        if let selectedSession = agents.selectedSession,
           selectedSession.workspaceSelection == selection {
            if !isSelectingSurfaceTab {
                retargetTabsAfterWorkspaceSelection(selection)
            }
            syncMountedSurfaces()
            requestSurfaceFocus(preferredSurfaceSlotForCurrentMainView())
            syncTerminalSurfaceActivation()
            return
        }
        if let firstSession = agents.firstSession(in: selection) {
            agents.selectSession(firstSession.id)
        } else {
            agents.selectedSessionID = nil
        }
        if !isSelectingSurfaceTab {
            retargetTabsAfterWorkspaceSelection(selection)
        }
        syncMountedSurfaces()
        requestSurfaceFocus(preferredSurfaceSlotForCurrentMainView())
        syncTerminalSurfaceActivation()
    }

    func toggleProjectCollapse(_ projectID: UUID) {
        projects.toggleProjectCollapse(projectID)
    }

    func openCommandBar(
        projectContextID: UUID? = nil,
        workspaceContext: WorkspaceSelection? = nil
    ) {
        shellStore.setCommandBarFocusRestore(true)
        commandBar.presentCommandList(
            projectContextID: projectContextID,
            workspaceContext: workspaceContext
        )
    }

    func closeCommandBar(restorePreviousFocus: Bool = true) {
        shellStore.setCommandBarFocusRestore(restorePreviousFocus)
        commandBar.close()
    }

    func toggleCommandBar() {
        commandBar.isPresented
            ? closeCommandBar(restorePreviousFocus: true)
            : openCommandBar()
    }

    func updateCommandQuery(_ query: String) {
        commandBar.query = query
        normalizeHighlightedCommandIndex(resetToFirstWhenOutOfRange: true)
    }

    func updateCommandTextInput(_ text: String) {
        commandBar.textInput = text
    }

    func moveHighlightedCommand(_ offset: Int) {
        let itemCount = visibleCommandBarItemCount()

        guard itemCount > 0 else {
            commandBar.highlightedIndex = 0
            return
        }

        normalizeHighlightedCommandIndex(resetToFirstWhenOutOfRange: false)
        let currentIndex = min(commandBar.highlightedIndex, itemCount - 1)
        let nextIndex = (currentIndex + offset + itemCount) % itemCount
        commandBar.highlightedIndex = nextIndex
    }

    func submitCommandBar() {
        switch commandBar.mode {
        case .commandList:
            executeHighlightedCommand()
        case .textInput:
            submitTextInputCommand()
        case .picker:
            submitHighlightedPickerItem()
        case .confirmation:
            confirmCommandBarAction()
        }
    }

    func executeHighlightedCommand() {
        let commands = filteredCommands
        guard !commands.isEmpty else {
            return
        }

        let selectedIndex = min(commandBar.highlightedIndex, commands.count - 1)
        executeCommand(
            commands[selectedIndex],
            projectContextID: commandBar.projectContextID,
            workspaceContext: commandBar.workspaceContext,
            source: .commandBar
        )
    }

    func executeCommand(
        _ command: CommandID,
        projectContextID: UUID? = nil,
        workspaceContext: WorkspaceSelection? = nil,
        source: CommandInvocationSource = .direct
    ) {
        Self.logger.debug("Execute command: \(command.rawValue, privacy: .public)")
        switch command {
        case .toggleCommandBar:
            toggleCommandBar()
        case .addProject:
            closeCommandBar(restorePreviousFocus: false)
            presentProjectImportPicker()
        case .addWorktree:
            beginAddWorktreeFlow(
                projectContextID: projectContextID,
                source: source,
                workspaceContext: workspaceContext
            )
        case .deleteWorktree:
            beginDeleteWorktreeFlow(
                source: source,
                workspaceContext: workspaceContext
            )
        case .selectProject:
            beginSelectProjectFlow()
        case .selectNextProject:
            selectAdjacentWorkspace(offset: 1)
            closeCommandBar(restorePreviousFocus: false)
        case .selectPreviousProject:
            selectAdjacentWorkspace(offset: -1)
            closeCommandBar(restorePreviousFocus: false)
        case .createAgent:
            beginCreateAgentFlow(
                workspaceContext: workspaceContext ?? commandBar.workspaceContext,
                source: source
            )
        case .createDefaultAgent:
            createDefaultAgent(
                workspaceContext: workspaceContext ?? commandBar.workspaceContext,
                source: source
            )
        case .deleteAgent:
            beginDeleteAgentFlow(source: source)
        case .selectPreviousAgent:
            selectAdjacentAgent(offset: -1)
            closeCommandBar(restorePreviousFocus: false)
        case .selectNextAgent:
            selectAdjacentAgent(offset: 1)
            closeCommandBar(restorePreviousFocus: false)
        case .openTerminalView:
            selectMainView(.terminal)
            closeCommandBar(restorePreviousFocus: false)
        case .openVSCodeView:
            selectMainView(.vscode)
            closeCommandBar(restorePreviousFocus: false)
        case .openAgentView:
            selectMainView(.agent)
            closeCommandBar(restorePreviousFocus: false)
        case .togglePreviewPane:
            togglePreview()
            closeCommandBar(restorePreviousFocus: false)
        case .toggleRightSidebar:
            toggleRightSidebar()
            closeCommandBar(restorePreviousFocus: false)
        case .toggleLeftSidebar:
            toggleLeftSidebar()
            closeCommandBar(restorePreviousFocus: false)
        case .quit:
            closeCommandBar(restorePreviousFocus: false)
            requestApplicationQuit()
        }
    }

    func addProject() {
        executeCommand(.addProject)
    }

    func addWorktree(to projectID: UUID) {
        openCommandBar(projectContextID: projectID)
        executeCommand(.addWorktree, projectContextID: projectID)
    }

    func cancelCommandBarConfirmation() {
        closeCommandBar()
    }

    func confirmCommandBarAction() {
        guard case let .confirmation(prompt) = commandBar.mode else {
            return
        }

        commandBar.notice = nil

        switch prompt.action {
        case let .deleteWorktree(projectID, worktreeID):
            guard let project = projects.project(id: projectID),
                  let worktree = projects.worktree(id: worktreeID)
            else {
                commandBar.notice = CommandBarNotice(
                    text: "Worktree no longer available.",
                    isError: true
                )
                return
            }

            let deletedSelection = WorkspaceSelection.worktree(worktreeID)
            let preservedMainView = layout.selectedMainView

            do {
                try gitService.deleteWorktree(
                    repositoryPath: URL(fileURLWithPath: project.path),
                    worktreePath: URL(fileURLWithPath: worktree.path)
                )

                cleanupResourcesForDeletedWorkspace(deletedSelection)
                refreshProjectsFromConfig()
                if let refreshedProject = projects.project(id: projectID) {
                    projects.select(.project(refreshedProject.id))
                }
                selectSurfaceForMainView(preservedMainView, selection: projects.selection)
                closeCommandBar(restorePreviousFocus: false)
            } catch {
                commandBar.notice = CommandBarNotice(
                    text: error.localizedDescription,
                    isError: true
                )
            }
        case let .deleteAgent(sessionID):
            deleteAgent(sessionID: sessionID)
            closeCommandBar(restorePreviousFocus: false)
        }
    }

    func addAgent(to selection: WorkspaceSelection) {
        openCommandBar(workspaceContext: selection)
        executeCommand(.createAgent, workspaceContext: selection, source: .commandBar)
    }

    func createDefaultAgent(
        workspaceContext: WorkspaceSelection?,
        source: CommandInvocationSource = .direct
    ) {
        guard let resolvedSelection = resolveWorkspaceContext(preferred: workspaceContext) else {
            presentCommandBarError(
                "Select project or worktree first, then run Create Default Agent.",
                source: source,
                workspaceContext: workspaceContext
            )
            return
        }

        guard projects.path(for: resolvedSelection) != nil else {
            presentCommandBarError(
                "Selected workspace has no launch path.",
                source: source,
                workspaceContext: workspaceContext
            )
            return
        }

        let defaultAgent = configuredDefaultAgent
        launchConfiguredAgent(
            workspaceSelection: resolvedSelection,
            agentName: defaultAgent.displayName,
            command: defaultAgent.normalizedCommand
        )
    }

    func selectSession(_ sessionID: UUID) {
        Self.logger.debug("Agent session switch requested: \(sessionID.uuidString, privacy: .public)")
        agents.selectSession(sessionID)
        if let session = agents.selectedSession {
            projects.select(session.workspaceSelection)
            Self.logger.debug(
                "Agent session selected: \(session.name, privacy: .public) workspace=\(session.workspaceSelection.stableID, privacy: .public)"
            )
            if !isSelectingSurfaceTab {
                selectOrCreateAgentSessionTab(session)
            }
        }
        requestSurfaceFocus(preferredSurfaceSlotForCurrentMainView())
        syncTerminalSurfaceActivation()
    }

    func deleteAgent(sessionID: UUID) {
        guard agents.sessions.contains(where: { $0.id == sessionID }) else {
            return
        }

        Self.logger.debug("Deleting agent session: \(sessionID.uuidString, privacy: .public)")
        terminalRegistry.release(id: .agent(sessionID))
        agents.removeSession(sessionID)
        removeSurfaceTabsForDeletedAgent(sessionID)
        syncTerminalSurfaceActivation()
    }

    @discardableResult
    func importProjects(from urls: [URL]) -> Int {
        let selectedPaths = urls.map(\.path).joined(separator: " | ")
        Self.logger.debug("Import requested for paths: \(selectedPaths, privacy: .public)")

        let newRecords = configStore.importedRecords(
            from: urls,
            existingRecords: projectConfig.projects
        )

        guard !newRecords.isEmpty else {
            Self.logger.error("Import skipped. No new directory records produced (duplicate, missing, or invalid paths).")
            print("Spurwechsel import: no new directory records (duplicate/missing/invalid).")
            return 0
        }

        let validRecords = newRecords.filter { record in
            do {
                _ = try gitService.repositorySnapshot(at: URL(fileURLWithPath: record.path))
                Self.logger.debug("Import validation passed for git repo: \(record.path, privacy: .public)")
                return true
            } catch {
                Self.logger.error("Import validation failed for path \(record.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                print("Spurwechsel import validation failed for \(record.path): \(error.localizedDescription)")
                return false
            }
        }

        guard !validRecords.isEmpty else {
            Self.logger.error("Import aborted. All selected folders failed git repository validation.")
            print("Spurwechsel import aborted: all selected folders failed git repository validation.")
            return 0
        }

        projectConfig.projects.append(contentsOf: validRecords)
        if let writeError = trySaveConfig() {
            Self.logger.error("Failed to save config at \(self.configStore.configURL.path, privacy: .public): \(writeError.localizedDescription, privacy: .public)")
            print("Spurwechsel config save failed at \(configStore.configURL.path): \(writeError.localizedDescription)")
        } else {
            Self.logger.debug("Saved config with \(self.projectConfig.projects.count, privacy: .public) total projects.")
        }

        refreshProjectsFromConfig()

        if let firstImportedRecord = validRecords.first,
           let importedProject = projects.projects.first(where: {
               $0.path == firstImportedRecord.path || $0.name == firstImportedRecord.displayName
           }) {
            selectWorkspace(.project(importedProject.id))
        }

        layout.showsRightSidebar = true
        layout.showsLeftSidebar = true
        selectOrCreateAgentTab(for: projects.selection)
        Self.logger.debug("Import completed. Added \(validRecords.count, privacy: .public) project(s).")
        return validRecords.count
    }

    private func beginAddWorktreeFlow(
        projectContextID: UUID?,
        source: CommandInvocationSource,
        workspaceContext: WorkspaceSelection?
    ) {
        guard let resolvedProjectID = resolveProjectContextID(preferred: projectContextID),
              let project = projects.project(id: resolvedProjectID)
        else {
            presentCommandBarError(
                "Select project first, then run Add Worktree.",
                source: source,
                projectContextID: projectContextID,
                workspaceContext: workspaceContext
            )
            return
        }

        commandBar.isPresented = true
        commandBar.projectContextID = resolvedProjectID
        commandBar.mode = .textInput(
            CommandBarTextPrompt(
                title: "Add Worktree (\(project.name))",
                placeholder: "Enter worktree name",
                submitTitle: "Create Worktree",
                action: .addWorktree(projectID: resolvedProjectID)
            )
        )
        commandBar.textInput = ""
        commandBar.notice = nil
        commandBar.resetQuery()
    }

    private func beginDeleteWorktreeFlow(
        source: CommandInvocationSource,
        workspaceContext: WorkspaceSelection?
    ) {
        guard let resolvedProjectID = resolveProjectContextID(preferred: commandBar.projectContextID),
              let project = projects.project(id: resolvedProjectID)
        else {
            presentCommandBarError(
                "Select project first, then run Delete Worktree.",
                source: source,
                projectContextID: commandBar.projectContextID,
                workspaceContext: workspaceContext
            )
            return
        }

        let items = project.worktrees.map { worktree in
            CommandBarPickerItem(
                id: "worktree-\(worktree.id.uuidString)",
                title: worktree.name,
                subtitle: worktree.branch,
                symbolName: "trash",
                payload: .deleteWorktree(projectID: resolvedProjectID, worktreeID: worktree.id)
            )
        }

        commandBar.isPresented = true
        commandBar.projectContextID = resolvedProjectID
        commandBar.mode = .picker(
            title: "Delete Worktree (\(project.name))",
            items: items,
            emptyMessage: "No worktrees available."
        )
        commandBar.notice = nil
        commandBar.resetQuery()
    }

    private func beginSelectProjectFlow() {
        let items = orderedWorkspaceNodesIncludingCollapsed.map { node in
            CommandBarPickerItem(
                id: "workspace-\(node.id)",
                title: node.title,
                subtitle: node.branchName,
                symbolName: node.isProject ? "folder" : "point.3.filled.connected.trianglepath.dotted",
                payload: .selectWorkspace(node.selection)
            )
        }

        commandBar.isPresented = true
        commandBar.mode = .picker(
            title: "Select Project",
            items: items,
            emptyMessage: "No projects available."
        )
        commandBar.notice = nil
        commandBar.resetQuery()
    }

    private func selectAdjacentWorkspace(offset: Int) {
        let orderedSelections = orderedWorkspaceNodesIncludingCollapsed.map(\.selection)
        guard let nextSelection = adjacentEntry(
            from: projects.selection,
            in: orderedSelections,
            offset: offset
        ) else {
            return
        }

        selectWorkspace(nextSelection)
    }

    private func selectAdjacentAgent(offset: Int) {
        let sessions = orderedAgentSessionsForSidebar
        guard !sessions.isEmpty else {
            return
        }

        let selectedSessionID = selectedAgent?.id
        let sessionIDs = sessions.map(\.id)
        guard let nextSessionID = adjacentEntry(
            from: selectedSessionID,
            in: sessionIDs,
            offset: offset
        ) else {
            return
        }

        selectSession(nextSessionID)
    }

    private func visibleCommandBarItemCount() -> Int {
        switch commandBar.mode {
        case .commandList:
            return filteredCommands.count
        case .picker:
            return filteredPickerItems.count
        default:
            return 0
        }
    }

    private func normalizeHighlightedCommandIndex(resetToFirstWhenOutOfRange: Bool) {
        let itemCount = visibleCommandBarItemCount()
        guard itemCount > 0 else {
            commandBar.highlightedIndex = 0
            return
        }

        if commandBar.highlightedIndex < itemCount {
            return
        }

        commandBar.highlightedIndex = resetToFirstWhenOutOfRange ? 0 : (itemCount - 1)
    }

    private func beginDeleteAgentFlow(source: CommandInvocationSource) {
        guard let session = selectedAgent else {
            presentCommandBarError(
                "Select an agent session first, then run Delete Agent.",
                source: source
            )
            return
        }

        commandBar.isPresented = true
        commandBar.mode = .confirmation(
            CommandBarConfirmationPrompt(
                title: "Delete Agent",
                message: "Close and remove \(session.name)?",
                confirmTitle: "Delete Agent",
                action: .deleteAgent(sessionID: session.id)
            )
        )
        commandBar.notice = nil
        commandBar.resetQuery()
    }

    private func beginCreateAgentFlow(
        workspaceContext: WorkspaceSelection?,
        source: CommandInvocationSource
    ) {
        guard let resolvedSelection = resolveWorkspaceContext(preferred: workspaceContext) else {
            presentCommandBarError(
                "Select project or worktree first, then run Create Agent.",
                source: source,
                workspaceContext: workspaceContext
            )
            return
        }

        guard projects.path(for: resolvedSelection) != nil else {
            presentCommandBarError(
                "Selected workspace has no launch path.",
                source: source,
                workspaceContext: workspaceContext
            )
            return
        }

        let items = configuredAgents.map { agent in
            CommandBarPickerItem(
                id: "agent-\(agent.displayName.lowercased().accessibilitySlug)",
                title: agent.displayName,
                subtitle: agent.normalizedCommand,
                symbolName: "sparkles.rectangle.stack",
                payload: .createAgent(
                    workspaceSelection: resolvedSelection,
                    agentName: agent.displayName,
                    command: agent.normalizedCommand
                )
            )
        }

        commandBar.isPresented = true
        commandBar.workspaceContext = resolvedSelection
        commandBar.mode = .picker(
            title: "Create Agent",
            items: items,
            emptyMessage: "No agents configured."
        )
        commandBar.notice = nil
        commandBar.resetQuery()
    }

    private func presentCommandBarError(
        _ text: String,
        source: CommandInvocationSource,
        projectContextID: UUID? = nil,
        workspaceContext: WorkspaceSelection? = nil
    ) {
        if source == .shortcut && !commandBar.isPresented {
            openCommandBar(projectContextID: projectContextID, workspaceContext: workspaceContext)
        }
        commandBar.notice = CommandBarNotice(text: text, isError: true)
        commandBar.mode = .commandList
    }

    private func submitTextInputCommand() {
        guard case let .textInput(prompt) = commandBar.mode else {
            return
        }

        commandBar.notice = nil

        switch prompt.action {
        case let .addWorktree(projectID):
            guard let project = projects.project(id: projectID) else {
                commandBar.notice = CommandBarNotice(
                    text: "Project no longer available.",
                    isError: true
                )
                return
            }

            do {
                let validatedName = try gitService.validateWorktreeName(commandBar.textInput)
                let createdWorktree = try gitService.createWorktree(
                    repositoryPath: URL(fileURLWithPath: project.path),
                    projectName: project.name,
                    worktreeName: validatedName
                )

                refreshProjectsFromConfig()
                if let selectedWorktree = projects.projects
                    .flatMap(\.worktrees)
                    .first(where: { normalizePath($0.path) == normalizePath(createdWorktree.path) }) {
                    selectWorkspace(.worktree(selectedWorktree.id))
                }

                closeCommandBar(restorePreviousFocus: false)
            } catch {
                commandBar.notice = CommandBarNotice(
                    text: error.localizedDescription,
                    isError: true
                )
            }
        }
    }

    private func submitHighlightedPickerItem() {
        let items = filteredPickerItems
        guard !items.isEmpty else {
            return
        }

        let selectedIndex = min(commandBar.highlightedIndex, items.count - 1)
        let item = items[selectedIndex]
        commandBar.notice = nil

        switch item.payload {
        case let .deleteWorktree(projectID, worktreeID):
            commandBar.mode = .confirmation(
                CommandBarConfirmationPrompt(
                    title: "Confirm Delete",
                    message: "Delete worktree '\(item.title)'?",
                    confirmTitle: "Delete Worktree",
                    action: .deleteWorktree(projectID: projectID, worktreeID: worktreeID)
                )
            )
        case let .selectWorkspace(selection):
            selectWorkspace(selection)
            closeCommandBar(restorePreviousFocus: false)
        case let .createAgent(workspaceSelection, agentName, command):
            launchConfiguredAgent(
                workspaceSelection: workspaceSelection,
                agentName: agentName,
                command: command
            )
        }
    }

    private var orderedWorkspaceNodesIncludingCollapsed: [WorkspaceNode] {
        projects.projects.flatMap { project in
            [
                WorkspaceNode(
                    selection: .project(project.id),
                    kind: .project,
                    parentProjectID: project.id,
                    title: project.name,
                    branchName: project.branch,
                    depth: 0,
                    hasChildren: !project.worktrees.isEmpty
                )
            ] + project.worktrees.map {
                WorkspaceNode(
                    selection: .worktree($0.id),
                    kind: .worktree,
                    parentProjectID: project.id,
                    title: $0.name,
                    branchName: $0.branch,
                    depth: 1,
                    hasChildren: false
                )
            }
        }
    }

    private var orderedAgentSessionsForSidebar: [AgentSession] {
        groupedAgentNodes.flatMap { _, sessions in
            sessions
        }
    }

    private func adjacentEntry<T: Equatable>(
        from current: T,
        in entries: [T],
        offset: Int
    ) -> T? {
        guard !entries.isEmpty else {
            return nil
        }

        guard let currentIndex = entries.firstIndex(of: current) else {
            return offset >= 0 ? entries.first : entries.last
        }

        let nextIndex = (currentIndex + offset + entries.count) % entries.count
        return entries[nextIndex]
    }

    private func adjacentEntry<T: Equatable>(
        from current: T?,
        in entries: [T],
        offset: Int
    ) -> T? {
        guard !entries.isEmpty else {
            return nil
        }

        guard let current else {
            return offset >= 0 ? entries.first : entries.last
        }

        return adjacentEntry(from: current, in: entries, offset: offset)
    }

    private func resolveProjectContextID(preferred: UUID?) -> UUID? {
        if let preferred, projects.project(id: preferred) != nil {
            return preferred
        }

        switch projects.selection {
        case let .project(projectID):
            if projects.project(id: projectID) != nil {
                return projectID
            }
        case let .worktree(worktreeID):
            if let project = projects.projectForWorktree(id: worktreeID) {
                return project.id
            }
        }

        return projects.projects.first?.id
    }

    private func resolveWorkspaceContext(preferred: WorkspaceSelection?) -> WorkspaceSelection? {
        if let preferred, projects.path(for: preferred) != nil {
            return preferred
        }

        if projects.path(for: projects.selection) != nil {
            return projects.selection
        }

        if let firstProject = projects.projects.first {
            return .project(firstProject.id)
        }

        return nil
    }

    private func launchConfiguredAgent(
        workspaceSelection: WorkspaceSelection,
        agentName: String,
        command: String
    ) {
        guard let workingDirectory = projects.path(for: workspaceSelection) else {
            commandBar.notice = CommandBarNotice(
                text: "Cannot resolve selected workspace directory.",
                isError: true
            )
            return
        }

        let session = agents.addAgent(
            to: workspaceSelection,
            launcherName: agentName,
            launchCommand: command,
            workingDirectory: workingDirectory
        )
        agents.updateStatus(for: session.id, status: .running)

        _ = terminalRegistry.acquire(id: .agent(session.id)) {
            let launchPlan = LocalShellTerminalSessionController.makeCommandLaunchPlan(
                command: command,
                workingDirectory: workingDirectory
            )
            return LocalShellTerminalSessionController(
                sessionID: session.id,
                startupTitle: agentName,
                launchPlan: launchPlan,
                terminalTheme: terminalTheme,
                onTitleChange: { [weak self] title in
                    guard let self else {
                        return
                    }
                    self.agents.updateTerminalTitle(for: session.id, title: title)
                },
                onProcessTerminated: { [weak self] exitCode in
                    guard let self else {
                        return
                    }
                    self.agents.updateExitCode(for: session.id, exitCode: exitCode)
                    let status: AgentSessionStatus
                    if let exitCode {
                        status = (exitCode == 0) ? .exited : .failed
                    } else {
                        status = .failed
                    }
                    self.agents.updateStatus(for: session.id, status: status)
                }
            )
        }

        projects.select(workspaceSelection)
        surfaceTabs.tabs.removeAll { tab in
            if case let .agentWorkspace(selectionID) = tab.id {
                return selectionID == workspaceSelection.stableID
            }
            return false
        }
        agents.selectSession(session.id)
        selectOrCreateAgentSessionTab(session)
        layout.showsLeftSidebar = true
        requestSurfaceFocus(.main)
        syncTerminalSurfaceActivation()
        closeCommandBar(restorePreviousFocus: false)
    }

    func initializeSurfaceTabs() {
        switch layout.selectedMainView {
        case .agent:
            if let selectedSession = selectedAgent {
                let tab = makeAgentSessionTab(selectedSession)
                surfaceTabs.tabs = [tab]
                surfaceTabs.selectedTabID = tab.id
            } else {
                let tab = makeAgentWorkspaceTab(for: projects.selection)
                surfaceTabs.tabs = [tab]
                surfaceTabs.selectedTabID = tab.id
            }
        case .terminal:
            let tab = makeWorkspaceTerminalTab(for: projects.selection)
            surfaceTabs.tabs = [tab]
            surfaceTabs.selectedTabID = tab.id
        case .vscode:
            let tab = makeVSCodeTab(for: projects.selection)
            surfaceTabs.tabs = [tab]
            surfaceTabs.selectedTabID = tab.id
        }
        syncMountedSurfaces()
    }

    private func upsertSurfaceTab(_ tab: SurfaceTab, select: Bool) {
        if let index = surfaceTabs.tabs.firstIndex(where: { $0.id == tab.id }) {
            surfaceTabs.tabs[index] = tab
        } else {
            surfaceTabs.tabs.append(tab)
        }
        if select {
            selectSurfaceTab(tab.id)
        }
    }

    private func selectOrCreateAgentTab(for selection: WorkspaceSelection) {
        if let selectedSession = agents.selectedSession,
           selectedSession.workspaceSelection == selection {
            selectOrCreateAgentSessionTab(selectedSession)
            return
        }

        if let firstSession = agents.firstSession(in: selection) {
            agents.selectSession(firstSession.id)
            selectOrCreateAgentSessionTab(firstSession)
            return
        }

        let tab = makeAgentWorkspaceTab(for: selection)
        upsertSurfaceTab(tab, select: true)
    }

    private func selectOrCreateAgentSessionTab(_ session: AgentSession) {
        let tab = makeAgentSessionTab(session)
        upsertSurfaceTab(tab, select: true)
    }

    private func selectOrCreateWorkspaceTerminalTab(for selection: WorkspaceSelection) {
        let tab = makeWorkspaceTerminalTab(for: selection)
        upsertSurfaceTab(tab, select: true)
    }

    private func selectOrCreateVSCodeTab(for selection: WorkspaceSelection) {
        let tab = makeVSCodeTab(for: selection)
        upsertSurfaceTab(tab, select: true)
    }

    private func selectSurfaceForMainView(
        _ mainView: MainViewKind,
        selection: WorkspaceSelection
    ) {
        switch mainView {
        case .agent:
            selectOrCreateAgentTab(for: selection)
        case .terminal:
            selectOrCreateWorkspaceTerminalTab(for: selection)
        case .vscode:
            selectOrCreateVSCodeTab(for: selection)
        }
    }

    private func selectSurfaceForCurrentMainView() {
        selectSurfaceForMainView(layout.selectedMainView, selection: projects.selection)
    }

    private func makeAgentSessionTab(_ session: AgentSession) -> SurfaceTab {
        SurfaceTab(
            id: .agentSession(session.id),
            title: session.name,
            workspaceSelection: session.workspaceSelection,
            sessionID: session.id
        )
    }

    private func makeAgentWorkspaceTab(for selection: WorkspaceSelection) -> SurfaceTab {
        let title = projects.node(for: selection)?.title ?? "Agent"
        return SurfaceTab(
            id: .agentWorkspace(selection.stableID),
            title: "Agent • \(title)",
            workspaceSelection: selection,
            sessionID: nil
        )
    }

    private func makeWorkspaceTerminalTab(for selection: WorkspaceSelection) -> SurfaceTab {
        let title = projects.node(for: selection)?.title ?? "terminal"
        return SurfaceTab(
            id: .workspaceTerminal(selection.stableID),
            title: "Terminal • \(title)",
            workspaceSelection: selection,
            sessionID: nil
        )
    }

    private func makeVSCodeTab(for selection: WorkspaceSelection) -> SurfaceTab {
        let title = projects.node(for: selection)?.title ?? "vscode"
        return SurfaceTab(
            id: .vscodeWorkspace(selection.stableID),
            title: "VSCode • \(title)",
            workspaceSelection: selection,
            sessionID: nil
        )
    }

    func selectSurfaceTab(_ id: SurfaceTabID) {
        guard let tab = surfaceTabs.tabs.first(where: { $0.id == id }) else {
            return
        }

        isSelectingSurfaceTab = true
        defer { isSelectingSurfaceTab = false }

        surfaceTabs.selectedTabID = id
        layout.selectMainView(tab.mainView)

        projects.select(tab.workspaceSelection)
        switch id {
        case let .agentSession(sessionID):
            agents.selectSession(sessionID)
        case .agentWorkspace:
            if let firstSession = agents.firstSession(in: tab.workspaceSelection) {
                agents.selectSession(firstSession.id)
            } else {
                agents.selectedSessionID = nil
            }
        case .workspaceTerminal:
            _ = projectTerminalController(for: tab.workspaceSelection)
        case .vscodeWorkspace:
            ensureVSCodeServerForSelectedWorkspace(forceRestart: false)
        }

        syncMountedSurfaces()
        requestSurfaceFocus(preferredSurfaceSlotForCurrentMainView())
        syncTerminalSurfaceActivation()
    }

    private func retargetTabsAfterWorkspaceSelection(_ selection: WorkspaceSelection) {
        guard let selectedID = surfaceTabs.selectedTabID else {
            selectOrCreateAgentTab(for: selection)
            return
        }

        switch selectedID {
        case .workspaceTerminal:
            selectOrCreateWorkspaceTerminalTab(for: selection)
        case .vscodeWorkspace:
            selectOrCreateVSCodeTab(for: selection)
        case .agentSession:
            if let selectedSession = agents.selectedSession {
                selectOrCreateAgentSessionTab(selectedSession)
            } else {
                selectOrCreateAgentTab(for: selection)
            }
        case .agentWorkspace:
            selectOrCreateAgentTab(for: selection)
        }
    }

    private func removeSurfaceTabsForDeletedAgent(_ sessionID: UUID) {
        let removedID = SurfaceTabID.agentSession(sessionID)
        let wasSelected = surfaceTabs.selectedTabID == removedID
        surfaceTabs.tabs.removeAll { $0.id == removedID }

        guard wasSelected else {
            syncMountedSurfaces()
            requestSurfaceFocus(preferredSurfaceSlotForCurrentMainView())
            return
        }

        selectSurfaceForCurrentMainView()
        syncMountedSurfaces()
        requestSurfaceFocus(preferredSurfaceSlotForCurrentMainView())
    }

    func preferredSurfaceSlotForCurrentMainView() -> SurfaceSlot {
        let preferred = layout.preferredFocusedSlot(for: layout.selectedMainView)
        if preferred == .preview,
           layout.previewEnabled,
           surfaceMountState.previewSurfaceID != nil {
            return .preview
        }
        return .main
    }

    func requestSurfaceFocus(_ preferredSlot: SurfaceSlot) {
        let resolvedSlot: SurfaceSlot
        switch preferredSlot {
        case .main:
            if surfaceMountState.mainSurfaceID != nil {
                resolvedSlot = .main
            } else if surfaceMountState.previewSurfaceID != nil {
                resolvedSlot = .preview
            } else {
                return
            }
        case .preview:
            if layout.previewEnabled,
               surfaceMountState.previewSurfaceID != nil {
                resolvedSlot = .preview
            } else if surfaceMountState.mainSurfaceID != nil {
                resolvedSlot = .main
            } else {
                return
            }
        }

        nextSurfaceFocusRequestID += 1
        shellStore.setSurfaceFocusRequest(SurfaceFocusRequest(
            id: nextSurfaceFocusRequestID,
            slot: resolvedSlot
        ))
    }

    func syncMountedSurfaces() {
        surfaceMountState.mount(surfaceTabs.selectedTabID, in: .main)

        guard layout.previewEnabled,
              let previewView = layout.selectedPreviewView,
              let previewSurfaceID = resolveSurfaceID(for: previewView, selection: projects.selection)
        else {
            surfaceMountState.mount(nil, in: .preview)
            return
        }

        if previewSurfaceID == surfaceTabs.selectedTabID {
            surfaceMountState.mount(nil, in: .preview)
            return
        }

        upsertSurfaceTabIfNeeded(for: previewSurfaceID, selection: projects.selection)
        surfaceMountState.mount(previewSurfaceID, in: .preview)
        if case .vscodeWorkspace = previewSurfaceID {
            ensureVSCodeServerForSelectedWorkspace(forceRestart: false)
        }
    }

    private func resolveSurfaceID(
        for previewView: PreviewViewKind,
        selection: WorkspaceSelection
    ) -> SurfaceTabID? {
        switch previewView {
        case .agent:
            if let selectedSession = agents.selectedSession,
               selectedSession.workspaceSelection == selection {
                return .agentSession(selectedSession.id)
            }
            if let firstSession = agents.firstSession(in: selection) {
                return .agentSession(firstSession.id)
            }
            return .agentWorkspace(selection.stableID)
        case .terminal:
            guard projects.path(for: selection) != nil else {
                return nil
            }
            return .workspaceTerminal(selection.stableID)
        case .vscode:
            guard projects.path(for: selection) != nil else {
                return nil
            }
            return .vscodeWorkspace(selection.stableID)
        }
    }

    private func upsertSurfaceTabIfNeeded(
        for id: SurfaceTabID,
        selection: WorkspaceSelection
    ) {
        if surfaceTabs.tabs.contains(where: { $0.id == id }) {
            return
        }
        switch id {
        case .agentSession:
            if let sessionID = resolvedAgentSessionID(for: id),
               let session = agents.sessions.first(where: { $0.id == sessionID }) {
                upsertSurfaceTab(makeAgentSessionTab(session), select: false)
            }
        case .agentWorkspace:
            upsertSurfaceTab(makeAgentWorkspaceTab(for: selection), select: false)
        case .workspaceTerminal:
            upsertSurfaceTab(makeWorkspaceTerminalTab(for: selection), select: false)
        case .vscodeWorkspace:
            upsertSurfaceTab(makeVSCodeTab(for: selection), select: false)
        }
    }

    private func resolvedAgentSessionID(for surfaceID: SurfaceTabID) -> UUID? {
        switch surfaceID {
        case let .agentSession(sessionID):
            return sessionID
        case let .agentWorkspace(selectionID):
            guard let tab = surfaceTabs.tabs.first(where: { $0.id == .agentWorkspace(selectionID) }) else {
                return nil
            }
            return agents.firstSession(in: tab.workspaceSelection)?.id
        default:
            return nil
        }
    }

    private func resolvedWorkspaceSelection(for surfaceID: SurfaceTabID) -> WorkspaceSelection? {
        switch surfaceID {
        case .workspaceTerminal, .agentWorkspace, .vscodeWorkspace:
            return surfaceTabs.tabs.first(where: { $0.id == surfaceID })?.workspaceSelection
        case let .agentSession(sessionID):
            return agents.sessions.first(where: { $0.id == sessionID })?.workspaceSelection
        }
    }

    func syncTerminalSurfaceActivation() {
        let activeSurfaceIDs = [surfaceMountState.mainSurfaceID, surfaceMountState.previewSurfaceID].compactMap { $0 }
        let activeAgentSessionID = terminalSurfacesAreForeground
            ? activeSurfaceIDs.compactMap { resolvedAgentSessionID(for: $0) }.first
            : nil
        let activeWorkspaceSelection = terminalSurfacesAreForeground
            ? activeSurfaceIDs.first(where: {
                if case .workspaceTerminal = $0 {
                    return true
                }
                return false
            }).flatMap { resolvedWorkspaceSelection(for: $0) }
            : nil
        let activeWorkspaceID = activeWorkspaceSelection?.stableID ?? "nil"
        Self.logger.debug(
            "Sync terminal activation: appActive=\(self.appIsActive, privacy: .public) windowKey=\(self.windowIsKey, privacy: .public) mainView=\(self.layout.selectedMainView.rawValue, privacy: .public) activeAgent=\(activeAgentSessionID?.uuidString ?? "nil", privacy: .public) activeWorkspace=\(activeWorkspaceID, privacy: .public)"
        )
        for session in agents.sessions {
            terminalRegistry.setAttached(
                id: .agent(session.id),
                attached: session.id == activeAgentSessionID
            )
        }

        let activeWorkspace = activeWorkspaceSelection
        for workspaceNode in projects.orderedNodes {
            terminalRegistry.setAttached(
                id: .workspace(workspaceNode.selection.stableID),
                attached: false
            )
        }
        if let activeWorkspace {
            _ = projectTerminalController(for: activeWorkspace)
            terminalRegistry.setAttached(
                id: .workspace(activeWorkspace.stableID),
                attached: true
            )
        }
    }

    func ensureVSCodeServerForSelectedWorkspace(forceRestart: Bool) {
        guard let workspacePath = projects.path(for: projects.selection),
              let workspaceNode = projects.node(for: projects.selection)
        else {
            vscodeServerRuntime.stop()
            vscodeServer.workspaceSelectionID = nil
            vscodeServer.workspaceName = nil
            vscodeServer.workspacePath = nil
            vscodeServer.serverAddress = nil
            vscodeServer.workspaceAddress = nil
            vscodeServer.status = .missingWorkspace
            vscodeServer.statusMessage = "Select project or worktree before starting code-server."
            vscodeServer.errorMessage = "No workspace path available for VSCode view."
            vscodeServer.lastOutputLine = nil
            return
        }

        let workspaceID = projects.selection.stableID
        let activeStatuses: Set<VSCodeServerStatus> = [.starting, .running, .authRequired, .stopping]
        vscodeServer.workspaceSelectionID = workspaceID
        vscodeServer.workspaceName = workspaceNode.title
        vscodeServer.workspacePath = workspacePath
        _ = ensureVSCodeWebRuntime(forWorkspaceID: workspaceID)

        if !forceRestart, activeStatuses.contains(vscodeServer.status) {
            if vscodeServer.status == .running {
                loadCurrentVSCodeWorkspaceInBrowser()
            } else if vscodeServer.status == .starting {
                let address = vscodeServer.serverAddress ?? vscodeServer.workspaceAddress ?? "127.0.0.1"
                vscodeServer.statusMessage = "Starting code-server for \(workspaceNode.title) at \(address)…"
            }
            return
        }

        vscodeServer.serverAddress = nil
        vscodeServer.workspaceAddress = nil
        vscodeServer.status = .starting
        vscodeServer.statusMessage = "Starting code-server for \(workspaceNode.title)…"
        vscodeServer.errorMessage = nil
        vscodeServer.lastOutputLine = nil
        invalidateVSCodeRuntimeAddresses()
        let configuredPort = projectConfig.codeServer.resolvedPort
        vscodeServerRuntime.start(
            workspaceID: workspaceID,
            workspacePath: workspacePath,
            port: configuredPort
        )
    }

    private func handleVSCodeWebNavigationFailed(message: String) {
        guard vscodeServer.status == .running else {
            return
        }
        vscodeServer.errorMessage = "code-server page failed to load: \(message)"
        vscodeServer.statusMessage = "code-server running, but browser load failed."
    }

    private func loadCurrentVSCodeWorkspaceInBrowser() {
        guard let serverAddress = vscodeServer.serverAddress,
              let serverURL = URL(string: serverAddress),
              let workspaceID = vscodeServer.workspaceSelectionID,
              let workspacePath = vscodeServer.workspacePath,
              let runtime = vscodeWebRuntimesByWorkspaceID[workspaceID],
              let workspaceURL = Self.codeServerFolderURL(
                serverURL: serverURL,
                workspacePath: workspacePath
              )
        else {
            return
        }

        let address = workspaceURL.absoluteString
        vscodeServer.workspaceAddress = address
        vscodeServer.status = .running
        if let workspaceName = vscodeServer.workspaceName {
            vscodeServer.statusMessage = "code-server active for \(workspaceName) at \(serverAddress)."
        } else {
            vscodeServer.statusMessage = "code-server active at \(serverAddress)."
        }
        vscodeServer.errorMessage = nil
        runtime.loadIfNeeded(workspaceURL)
    }

    func handleVSCodeServerEvent(_ event: VSCodeServerRuntime.Event) {
        switch event {
        case let .starting(_, _, serverURL):
            let displayName = vscodeServer.workspaceName ?? "selected workspace"
            vscodeServer.status = .starting
            vscodeServer.statusMessage = "Starting code-server for \(displayName) at \(serverURL.host ?? "127.0.0.1"):\(serverURL.port ?? 0)…"
            vscodeServer.errorMessage = nil
            vscodeServer.lastOutputLine = nil
            vscodeServer.serverAddress = serverURL.absoluteString
            vscodeServer.workspaceAddress = nil
        case let .outputLine(line):
            vscodeServer.lastOutputLine = line
        case let .authRequired(line):
            vscodeServer.status = .authRequired
            vscodeServer.statusMessage = "Authentication needed for code-server. Resolve auth, then re-enter VSCode view."
            vscodeServer.errorMessage = line
            vscodeServer.lastOutputLine = line
        case let .serverReady(url):
            vscodeServer.serverAddress = url.absoluteString
            loadCurrentVSCodeWorkspaceInBrowser()
        case .stopped:
            if vscodeServer.status == .missingWorkspace {
                return
            }
            vscodeServer.status = .stopped
            vscodeServer.serverAddress = nil
            vscodeServer.workspaceAddress = nil
            vscodeServer.statusMessage = "code-server stopped. Re-enter VSCode view to restart."
            vscodeServer.errorMessage = nil
            vscodeServer.lastOutputLine = nil
            invalidateVSCodeRuntimeAddresses()
        case let .failed(reason, message, lastOutputLine):
            switch reason {
            case .cliMissing:
                vscodeServer.status = .cliMissing
            case .portInUse:
                vscodeServer.status = .portInUse
            case .startupFailed:
                vscodeServer.status = .startupFailed
            case .authRequired:
                vscodeServer.status = .authRequired
            case .urlNotFound:
                vscodeServer.status = .urlNotFound
            }
            vscodeServer.statusMessage = message
            vscodeServer.errorMessage = message
            vscodeServer.lastOutputLine = lastOutputLine
            vscodeServer.serverAddress = nil
            vscodeServer.workspaceAddress = nil
            invalidateVSCodeRuntimeAddresses()
        }
    }

    private static func codeServerFolderURL(serverURL: URL, workspacePath: String) -> URL? {
        guard var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = "/"
        components.queryItems = [
            URLQueryItem(name: "folder", value: workspacePath)
        ]
        return components.url
    }

    private func ensureVSCodeWebRuntime(forWorkspaceID workspaceID: String) -> EmbeddedWebViewRuntime {
        if let runtime = vscodeWebRuntimesByWorkspaceID[workspaceID] {
            vscodeMountedWorkspaceIDs.removeAll { $0 == workspaceID }
            vscodeMountedWorkspaceIDs.append(workspaceID)
            return runtime
        }

        let runtime = EmbeddedWebViewRuntime()
        runtime.handlers.onNavigationFailed = { [weak self] _, message in
            self?.handleVSCodeWebNavigationFailed(
                forWorkspaceID: workspaceID,
                message: message
            )
        }
        vscodeWebRuntimesByWorkspaceID[workspaceID] = runtime
        vscodeMountedWorkspaceIDs.removeAll { $0 == workspaceID }
        vscodeMountedWorkspaceIDs.append(workspaceID)
        evictStaleVSCodeWebRuntimesIfNeeded()
        return runtime
    }

    private func evictStaleVSCodeWebRuntimesIfNeeded() {
        while vscodeMountedWorkspaceIDs.count > Self.maxWarmVSCodeRuntimes {
            guard let oldestWorkspaceID = vscodeMountedWorkspaceIDs.first else {
                return
            }
            removeVSCodeWebRuntime(forWorkspaceID: oldestWorkspaceID)
        }
    }

    private func invalidateVSCodeRuntimeAddresses() {
        for runtime in vscodeWebRuntimesByWorkspaceID.values {
            runtime.invalidateLastRequestedAddress()
        }
    }

    private func removeVSCodeWebRuntime(forWorkspaceID workspaceID: String) {
        if let runtime = vscodeWebRuntimesByWorkspaceID.removeValue(forKey: workspaceID) {
            runtime.resetToBlank()
        }
        vscodeMountedWorkspaceIDs.removeAll { $0 == workspaceID }
    }

    private func pruneVSCodeWebRuntimes(keepingWorkspaceIDs: Set<String>) {
        let staleWorkspaceIDs = Set(vscodeWebRuntimesByWorkspaceID.keys)
            .subtracting(keepingWorkspaceIDs)
        for workspaceID in staleWorkspaceIDs {
            removeVSCodeWebRuntime(forWorkspaceID: workspaceID)
        }
        vscodeMountedWorkspaceIDs = vscodeMountedWorkspaceIDs.filter { keepingWorkspaceIDs.contains($0) }
    }

    private func removeAgentSessions(in selection: WorkspaceSelection) {
        let sessionIDs = agents.sessions
            .filter { $0.workspaceSelection == selection }
            .map(\.id)
        let sessionIDSet = Set(sessionIDs)

        guard !sessionIDs.isEmpty else {
            return
        }

        for sessionID in sessionIDs {
            terminalRegistry.release(id: .agent(sessionID))
            agents.removeSession(sessionID)
        }

        surfaceTabs.tabs.removeAll { tab in
            guard let sessionID = tab.sessionID else {
                return false
            }
            return sessionIDSet.contains(sessionID)
        }
    }

    private func cleanupResourcesForDeletedWorkspace(_ selection: WorkspaceSelection) {
        let workspaceID = selection.stableID

        removeAgentSessions(in: selection)
        terminalRegistry.release(id: .workspace(workspaceID))
        removeVSCodeWebRuntime(forWorkspaceID: workspaceID)
        surfaceTabs.tabs.removeAll { tab in
            switch tab.id {
            case let .agentWorkspace(selectionID),
                 let .workspaceTerminal(selectionID),
                 let .vscodeWorkspace(selectionID):
                return selectionID == workspaceID
            case .agentSession:
                return false
            }
        }
    }

    private func pruneAgentSessions(keepingSelections: Set<WorkspaceSelection>) {
        let staleSessionIDs = agents.sessions
            .filter { !keepingSelections.contains($0.workspaceSelection) }
            .map(\.id)
        let staleSessionIDSet = Set(staleSessionIDs)

        guard !staleSessionIDs.isEmpty else {
            return
        }

        for sessionID in staleSessionIDs {
            terminalRegistry.release(id: .agent(sessionID))
            agents.removeSession(sessionID)
        }

        surfaceTabs.tabs.removeAll { tab in
            guard let sessionID = tab.sessionID else {
                return false
            }
            return staleSessionIDSet.contains(sessionID)
        }
    }

    private func handleVSCodeWebNavigationFailed(
        forWorkspaceID workspaceID: String,
        message: String
    ) {
        guard vscodeServer.workspaceSelectionID == workspaceID else {
            return
        }
        handleVSCodeWebNavigationFailed(message: message)
    }

    func refreshProjectsFromConfig() {
        Self.logger.debug("Refreshing projects from config. Persisted count: \(self.projectConfig.projects.count, privacy: .public)")
        var refreshedProjects: [Project] = []
        for record in projectConfig.projects {
            let normalizedRecordPath = normalizePath(record.path)
            let snapshot: GitRepositorySnapshot
            do {
                snapshot = try gitService.repositorySnapshot(at: URL(fileURLWithPath: normalizedRecordPath))
            } catch {
                Self.logger.error("Skipping persisted project \(record.displayName, privacy: .public) at \(normalizedRecordPath, privacy: .public): \(error.localizedDescription, privacy: .public)")
                print("Spurwechsel skip persisted project \(record.displayName) at \(normalizedRecordPath): \(error.localizedDescription)")
                continue
            }

            let existingProject: Project?
            if let existingProjectID = projectIDsByRecordPath[normalizedRecordPath] {
                existingProject = projects.project(id: existingProjectID)
            } else {
                existingProject = projects.projects.first(where: {
                    normalizePath($0.path) == normalizedRecordPath
                })
            }
            let projectID = existingProject?.id ?? projectIDsByRecordPath[normalizedRecordPath] ?? UUID()
            projectIDsByRecordPath[normalizedRecordPath] = projectID

            let existingWorktreeIDsByPath = Dictionary(
                uniqueKeysWithValues: (existingProject?.worktrees ?? []).map {
                    (normalizePath($0.path), $0.id)
                }
            )

            let discoveredWorktrees = snapshot.worktrees
                .filter { !$0.isPrimary }
                .map { snapshotWorktree -> Worktree in
                    let normalizedWorktreePath = normalizePath(snapshotWorktree.path)
                    let worktreeID = existingWorktreeIDsByPath[normalizedWorktreePath]
                        ?? worktreeIDsByPath[normalizedWorktreePath]
                        ?? UUID()
                    worktreeIDsByPath[normalizedWorktreePath] = worktreeID

                    return Worktree(
                        id: worktreeID,
                        name: snapshotWorktree.name,
                        branch: snapshotWorktree.branch,
                        path: normalizedWorktreePath,
                        isPrimary: false
                    )
                }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

            refreshedProjects.append(
                Project(
                    id: projectID,
                    name: record.displayName,
                    branch: snapshot.currentBranch,
                    path: snapshot.repositoryRootPath,
                    worktrees: discoveredWorktrees
                )
            )
            Self.logger.debug("Loaded project \(record.displayName, privacy: .public) branch \(snapshot.currentBranch, privacy: .public) worktrees \(snapshot.worktrees.count - 1, privacy: .public)")
        }

        projects.replaceProjects(refreshedProjects)
        let validSelections = Set(projects.orderedNodes.map(\.selection))
        pruneAgentSessions(keepingSelections: validSelections)
        let validWorkspaceIDs = validSelections.map { TerminalSessionID.workspace($0.stableID) }
        let validAgentIDs = agents.sessions.map { TerminalSessionID.agent($0.id) }
        terminalRegistry.prune(keepingIDs: Set(validWorkspaceIDs).union(validAgentIDs))
        pruneVSCodeWebRuntimes(keepingWorkspaceIDs: Set(validSelections.map(\.stableID)))
        pruneSurfaceTabs(keepingSelections: validSelections)
        Self.logger.debug("Refresh done. Active projects in UI: \(self.projects.projects.count, privacy: .public)")
    }

    private func pruneSurfaceTabs(keepingSelections: Set<WorkspaceSelection>) {
        let validSessionIDs = Set(agents.sessions.map(\.id))
        surfaceTabs.tabs.removeAll { tab in
            guard keepingSelections.contains(tab.workspaceSelection) else {
                return true
            }
            if let sessionID = tab.sessionID {
                return !validSessionIDs.contains(sessionID)
            }
            return false
        }

        if let selectedID = surfaceTabs.selectedTabID,
           surfaceTabs.tabs.contains(where: { $0.id == selectedID }) {
            syncMountedSurfaces()
            requestSurfaceFocus(preferredSurfaceSlotForCurrentMainView())
            return
        }

        selectSurfaceForCurrentMainView()
        syncMountedSurfaces()
        requestSurfaceFocus(preferredSurfaceSlotForCurrentMainView())
    }

    private func presentProjectImportPicker() {
        guard let selectedURLs = importURLsProvider() else {
            Self.logger.debug("Import picker dismissed without selection.")
            return
        }

        let selectedPaths = selectedURLs.map(\.path).joined(separator: " | ")
        Self.logger.debug("Import picker selected: \(selectedPaths, privacy: .public)")
        _ = importProjects(from: selectedURLs)
    }

    private func trySaveConfig() -> Error? {
        do {
            fileConfig = UserConfigFile.explicit(from: projectConfig)
            try configStore.save(fileConfig)
            return nil
        } catch {
            return error
        }
    }
}

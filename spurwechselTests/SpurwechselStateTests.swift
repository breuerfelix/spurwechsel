import AppKit
import XCTest
import SwiftTerm
@testable import spurwechsel

final class SpurwechselStateTests: XCTestCase {

    func testPreferredPreviewWidthStartsUnset() {
        let layout = AppLayoutState()
        XCTAssertNil(layout.preferredPreviewWidth)
    }

    func testPreferredPreviewWidthClampsToAllowedRange() {
        var layout = AppLayoutState()

        layout.setPreferredPreviewWidth(120, allowedRange: 260...780)
        XCTAssertEqual(layout.preferredPreviewWidth, 260)

        layout.setPreferredPreviewWidth(512, allowedRange: 260...780)
        XCTAssertEqual(layout.preferredPreviewWidth, 512)

        layout.setPreferredPreviewWidth(990, allowedRange: 260...780)
        XCTAssertEqual(layout.preferredPreviewWidth, 780)
    }

    func testPreviewToggleKeepsPreferredPreviewWidth() {
        var layout = AppLayoutState()
        layout.selectMainView(.agent)
        layout.selectPreviewView(.terminal)
        layout.setPreferredPreviewWidth(444, allowedRange: 260...780)

        layout.togglePreview()
        layout.togglePreview()

        XCTAssertEqual(layout.preferredPreviewWidth, 444)
    }

    func testLayoutToggleKeepsPreviewSelectionPerView() {
        var layout = AppLayoutState()
        layout.selectMainView(.agent)
        layout.selectPreviewView(.terminal)

        XCTAssertTrue(layout.previewEnabled)
        XCTAssertEqual(layout.selectedPreviewView, .terminal)

        layout.togglePreview()
        XCTAssertFalse(layout.previewEnabled)

        layout.selectMainView(.vscode)
        XCTAssertFalse(layout.previewEnabled)

        layout.selectMainView(.agent)
        XCTAssertFalse(layout.previewEnabled)

        layout.togglePreview()
        XCTAssertTrue(layout.previewEnabled)
    }

    func testTerminalMainViewSuppressesTerminalPreview() {
        var layout = AppLayoutState()
        layout.selectMainView(.agent)
        layout.selectPreviewView(.terminal)
        XCTAssertTrue(layout.previewEnabled)

        layout.selectMainView(.terminal)
        XCTAssertFalse(layout.previewEnabled)
        XCTAssertNil(layout.selectedPreviewView)
    }

    func testPreviewStateRestoresWhenSwitchingBackToView() {
        var layout = AppLayoutState()
        layout.selectMainView(.agent)
        layout.selectPreviewView(.terminal)
        XCTAssertTrue(layout.previewEnabled)
        XCTAssertEqual(layout.selectedPreviewView, .terminal)

        layout.selectMainView(.vscode)
        XCTAssertFalse(layout.previewEnabled)
        XCTAssertNil(layout.selectedPreviewView)

        layout.selectMainView(.agent)
        XCTAssertTrue(layout.previewEnabled)
        XCTAssertEqual(layout.selectedPreviewView, .terminal)

        layout.togglePreview()
        layout.selectMainView(.vscode)
        layout.selectMainView(.agent)
        XCTAssertFalse(layout.previewEnabled)
    }

    func testLayoutRemembersFocusedSlotPerMainView() {
        var layout = AppLayoutState()
        XCTAssertEqual(layout.preferredFocusedSlot(for: .agent), .main)

        layout.rememberFocusedSlot(.preview)
        XCTAssertEqual(layout.preferredFocusedSlot(for: .agent), .preview)

        layout.selectMainView(.vscode)
        XCTAssertEqual(layout.preferredFocusedSlot(for: .vscode), .main)

        layout.rememberFocusedSlot(.main)
        XCTAssertEqual(layout.preferredFocusedSlot(for: .agent), .preview)
        XCTAssertEqual(layout.preferredFocusedSlot(for: .vscode), .main)
    }

    func testTerminalMainViewHidesLeftSidebarWithoutMutatingPreference() {
        var layout = PreviewFixtures.layoutState
        layout.showsLeftSidebar = true

        layout.selectMainView(.terminal)

        XCTAssertFalse(layout.effectiveShowsLeftSidebar)
        XCTAssertTrue(layout.showsLeftSidebar)
    }

    @MainActor
    func testSelectPreviewViewRequestsPreviewFocus() {
        let store = SpurwechselStore()

        store.selectPreviewView(.terminal)

        XCTAssertEqual(store.surfaceFocusRequest?.slot, .preview)
    }

    @MainActor
    func testTogglePreviewRequestsFocusForOpenedPane() {
        let store = SpurwechselStore()

        store.togglePreview()
        XCTAssertTrue(store.layout.previewEnabled)
        XCTAssertEqual(store.surfaceFocusRequest?.slot, .preview)

        store.togglePreview()
        XCTAssertFalse(store.layout.previewEnabled)
        XCTAssertEqual(store.surfaceFocusRequest?.slot, .main)
    }

    @MainActor
    func testSelectMainViewRestoresRememberedFocusedPane() {
        let store = SpurwechselStore()

        store.selectPreviewView(.terminal)
        store.recordFocusedSurfaceSlot(.preview)

        store.selectMainView(.vscode)
        XCTAssertEqual(store.surfaceFocusRequest?.slot, .main)

        store.selectMainView(.agent)
        XCTAssertEqual(store.surfaceFocusRequest?.slot, .preview)
    }

    func testProjectsStateCollapseHidesWorktreesFromOrderedNodes() {
        var state = PreviewFixtures.projectsState

        XCTAssertTrue(state.orderedNodes.contains { $0.title == "editor" })

        state.toggleProjectCollapse(PreviewFixtures.draftframeProject.id)

        XCTAssertFalse(state.orderedNodes.contains { $0.title == "editor" })
        XCTAssertFalse(state.orderedNodes.contains { $0.title == "exporting" })
    }

    func testProjectsStateAddWorktreeSelectsNewWorktree() {
        var state = PreviewFixtures.projectsState

        let worktree = state.addWorktree(to: PreviewFixtures.orbitProject.id)

        XCTAssertNotNil(worktree)
        if case let .worktree(selectedID) = state.selection {
            XCTAssertEqual(selectedID, worktree?.id)
        } else {
            XCTFail("Expected worktree selection")
        }
        XCTAssertTrue(state.projects.contains { project in
            project.id == PreviewFixtures.orbitProject.id && project.worktrees.contains(where: { $0.id == worktree?.id })
        })
    }

    func testAgentStateAddAgentSelectsNewSession() {
        var state = PreviewFixtures.agentState

        let newSession = state.addAgent(
            to: .project(PreviewFixtures.tiltrunProject.id),
            launcherName: "codex",
            launchCommand: "codex",
            workingDirectory: "/tmp/repo"
        )

        XCTAssertEqual(state.selectedSessionID, newSession.id)
        XCTAssertEqual(state.sessions(for: .project(PreviewFixtures.tiltrunProject.id)).count, 1)
        XCTAssertEqual(newSession.status, .launching)
        XCTAssertEqual(newSession.launchCommand, "codex")
    }

    @MainActor
    func testStoreSelectingSessionSyncsWorkspaceSelection() {
        let project = Project(name: "Repo", branch: "main", path: "/tmp/repo")
        let projectsState = ProjectsState.fromImportedProjects([project])
        let session = AgentSession(
            workspaceSelection: .project(project.id),
            name: "codex-1",
            status: .running,
            launcherName: "codex",
            launchCommand: "codex",
            workingDirectory: "/tmp/repo",
            terminalTitle: "codex",
            lastActivity: "now",
            exitCode: nil
        )
        let agentState = AgentState(
            sessions: [session],
            selectedSessionID: nil,
            nextAgentCount: 2
        )
        let store = SpurwechselStore(projects: projectsState, agents: agentState)

        store.selectSession(session.id)

        XCTAssertEqual(store.projects.selection, .project(project.id))
    }

    @MainActor
    func testSelectWorkspaceKeepsExplicitSessionSelectionWithinSameWorkspace() {
        let project = Project(name: "Repo", branch: "main", path: "/tmp/repo")
        let projectsState = ProjectsState.fromImportedProjects([project])
        let sessionOne = AgentSession(
            workspaceSelection: .project(project.id),
            name: "codex-1",
            status: .running,
            launcherName: "codex",
            launchCommand: "codex",
            workingDirectory: "/tmp/repo",
            terminalTitle: "codex",
            lastActivity: "now",
            exitCode: nil
        )
        let sessionTwo = AgentSession(
            workspaceSelection: .project(project.id),
            name: "claude-2",
            status: .running,
            launcherName: "claude",
            launchCommand: "claude",
            workingDirectory: "/tmp/repo",
            terminalTitle: "claude",
            lastActivity: "now",
            exitCode: nil
        )
        let agentState = AgentState(
            sessions: [sessionOne, sessionTwo],
            selectedSessionID: sessionTwo.id,
            nextAgentCount: 3
        )
        let store = SpurwechselStore(projects: projectsState, agents: agentState)

        store.selectWorkspace(.project(project.id))

        XCTAssertEqual(store.agents.selectedSessionID, sessionTwo.id)
        XCTAssertEqual(store.selectedAgent?.id, sessionTwo.id)
    }

    @MainActor
    func testSelectedAgentFallsBackToFirstSessionInSelectedWorkspace() {
        let projectA = Project(name: "RepoA", branch: "main", path: "/tmp/repo-a")
        let projectB = Project(name: "RepoB", branch: "main", path: "/tmp/repo-b")
        let projectsState = ProjectsState.fromImportedProjects([projectA, projectB])
        let sessionA = AgentSession(
            workspaceSelection: .project(projectA.id),
            name: "codex-1",
            status: .running,
            launcherName: "codex",
            launchCommand: "codex",
            workingDirectory: "/tmp/repo-a",
            terminalTitle: "codex",
            lastActivity: "now",
            exitCode: nil
        )
        var agentState = AgentState(
            sessions: [sessionA],
            selectedSessionID: nil,
            nextAgentCount: 2
        )
        var store = SpurwechselStore(projects: projectsState, agents: agentState)

        XCTAssertEqual(store.selectedAgent?.id, sessionA.id)

        store.selectWorkspace(.project(projectB.id))
        XCTAssertNil(store.selectedAgent)

        agentState.selectedSessionID = sessionA.id
        store = SpurwechselStore(projects: projectsState, agents: agentState)
        XCTAssertEqual(store.selectedAgent?.id, sessionA.id)
    }

    @MainActor
    func testResolvedAgentSessionDoesNotBorrowFromDifferentWorkspace() {
        let projectA = Project(name: "RepoA", branch: "main", path: "/tmp/repo-a")
        let projectB = Project(name: "RepoB", branch: "main", path: "/tmp/repo-b")
        let projectsState = ProjectsState.fromImportedProjects([projectA, projectB])
        let sessionA = AgentSession(
            workspaceSelection: .project(projectA.id),
            name: "codex-1",
            status: .running,
            launcherName: "codex",
            launchCommand: "codex",
            workingDirectory: "/tmp/repo-a",
            terminalTitle: "codex",
            lastActivity: "now",
            exitCode: nil
        )
        let agentState = AgentState(
            sessions: [sessionA],
            selectedSessionID: sessionA.id,
            nextAgentCount: 2
        )
        let store = SpurwechselStore(projects: projectsState, agents: agentState)

        XCTAssertNil(store.resolvedAgentSession(sessionID: nil, in: .project(projectB.id)))
        XCTAssertEqual(
            store.resolvedAgentSession(sessionID: nil, in: .project(projectA.id))?.id,
            sessionA.id
        )
    }

    @MainActor
    func testAgentTerminalHostViewPresentsControllerTerminalViewDirectly() {
        let controller = LocalShellTerminalSessionController(
            sessionID: UUID(),
            startupTitle: "test",
            launchPlan: .init(executable: "/bin/zsh", args: []),
            startProcess: false,
            onTitleChange: { _ in },
            onProcessTerminated: { _ in }
        )
        let hostView = AgentTerminalHostView(controller: controller, isActive: true)

        let presentedView = hostView.makeNSView(context: Context())

        XCTAssertTrue(presentedView === controller.terminalView)
    }

    @MainActor
    func testTerminalRestorationBufferEvictsOldSnapshots() {
        let controller = LocalShellTerminalSessionController(
            sessionID: UUID(),
            startupTitle: "test",
            launchPlan: .init(executable: "/bin/zsh", args: []),
            startProcess: false,
            onTitleChange: { _ in },
            onProcessTerminated: { _ in }
        )

        let entries = LocalShellTerminalSessionController.restorationSnapshotLimit + 7
        for _ in 0..<entries {
            controller.appendRestorationSnapshotForTesting(
                NSImage(size: NSSize(width: 16, height: 10))
            )
        }

        XCTAssertEqual(
            controller.restorationSnapshotCount,
            LocalShellTerminalSessionController.restorationSnapshotLimit
        )
    }

    @MainActor
    func testTerminalRestorationSnapshotCapturesWhileDetached() {
        let controller = LocalShellTerminalSessionController(
            sessionID: UUID(),
            startupTitle: "test",
            launchPlan: .init(executable: "/bin/zsh", args: []),
            startProcess: false,
            onTitleChange: { _ in },
            onProcessTerminated: { _ in }
        )

        XCTAssertEqual(controller.restorationSnapshotCount, 0)
        controller.markSurfaceInactive()

        XCTAssertEqual(controller.restorationSnapshotCount, 1)
    }

    func testAgentStateRemoveSessionDeletesAndFallsBackToSameWorkspace() {
        var state = PreviewFixtures.agentState
        let sessionToRemove = state.sessions.first!
        let sameWorkspaceSessions = state.sessions.filter { $0.workspaceSelection == sessionToRemove.workspaceSelection && $0.id != sessionToRemove.id }
        let expectedFallbackID = sameWorkspaceSessions.first?.id

        state.removeSession(sessionToRemove.id)

        XCTAssertFalse(state.sessions.contains(where: { $0.id == sessionToRemove.id }))
        XCTAssertEqual(state.selectedSessionID, expectedFallbackID)
    }

    func testAgentStateRemoveSessionClearsSelectionWhenNoFallback() {
        var state = AgentState(sessions: [], selectedSessionID: nil, nextAgentCount: 1)
        let session = AgentSession(
            workspaceSelection: .project(PreviewFixtures.tiltrunProject.id),
            name: "codex-1",
            status: .running,
            launcherName: "codex",
            launchCommand: "codex",
            workingDirectory: "/tmp/repo",
            terminalTitle: "codex",
            lastActivity: "now",
            exitCode: nil
        )
        state.sessions = [session]
        state.selectedSessionID = session.id

        state.removeSession(session.id)

        XCTAssertTrue(state.sessions.isEmpty)
        XCTAssertNil(state.selectedSessionID)
    }

    @MainActor
    func testDeleteAgentKeepsCurrentAgentViewWhenTerminalTabExists() {
        let project = Project(name: "Repo", branch: "main", path: "/tmp/repo")
        let projectsState = ProjectsState.fromImportedProjects([project])
        let session = AgentSession(
            workspaceSelection: .project(project.id),
            name: "codex-1",
            status: .running,
            launcherName: "codex",
            launchCommand: "codex",
            workingDirectory: "/tmp/repo",
            terminalTitle: "codex",
            lastActivity: "now",
            exitCode: nil
        )
        let agentState = AgentState(
            sessions: [session],
            selectedSessionID: session.id,
            nextAgentCount: 2
        )
        let store = SpurwechselStore(projects: projectsState, agents: agentState)

        store.selectMainView(.terminal)
        store.selectMainView(.agent)
        XCTAssertEqual(store.layout.selectedMainView, .agent)

        store.deleteAgent(sessionID: session.id)

        XCTAssertEqual(store.layout.selectedMainView, .agent)
        XCTAssertEqual(store.surfaceTabs.selectedTab?.mainView, .agent)
        XCTAssertTrue(store.agents.sessions.isEmpty)
    }

    @MainActor
    func testStoreExecuteCommandOpenAgentViewChangesMainView() {
        let store = SpurwechselStore()
        store.layout.selectedMainView = .terminal

        store.executeCommand(.openAgentView)

        XCTAssertEqual(store.layout.selectedMainView, .agent)
        XCTAssertFalse(store.commandBar.isPresented)
    }

    @MainActor
    func testStoreExecuteCommandTogglePreviewPaneTogglesPreview() {
        let store = SpurwechselStore()
        store.layout.selectMainView(.agent)
        let initialEnabled = store.layout.previewEnabled

        store.executeCommand(.togglePreviewPane)

        XCTAssertEqual(store.layout.previewEnabled, !initialEnabled)
        XCTAssertFalse(store.commandBar.isPresented)
    }

    @MainActor
    func testStoreExecuteCommandToggleLeftSidebarTogglesSidebar() {
        let store = SpurwechselStore()
        store.layout.showsLeftSidebar = false

        store.executeCommand(.toggleLeftSidebar)

        XCTAssertTrue(store.layout.showsLeftSidebar)
        XCTAssertFalse(store.commandBar.isPresented)
    }

    @MainActor
    func testStoreExecuteCommandToggleRightSidebarTogglesSidebar() {
        let store = SpurwechselStore()
        store.layout.showsRightSidebar = false

        store.executeCommand(.toggleRightSidebar)

        XCTAssertTrue(store.layout.showsRightSidebar)
        XCTAssertFalse(store.commandBar.isPresented)
    }

    @MainActor
    func testCommandBarMoveHighlightedCommandWrapsInCommandAndPickerModes() {
        let store = SpurwechselStore()
        store.openCommandBar()

        store.moveHighlightedCommand(-1)
        XCTAssertEqual(store.commandBar.highlightedIndex, store.filteredCommands.count - 1)

        store.commandBar.mode = .picker(
            title: "Pick",
            items: [
                CommandBarPickerItem(
                    id: "one",
                    title: "One",
                    subtitle: "first",
                    symbolName: "sparkles.rectangle.stack",
                    payload: .createAgent(workspaceSelection: .none, agentName: "one", command: "one")
                ),
                CommandBarPickerItem(
                    id: "two",
                    title: "Two",
                    subtitle: "second",
                    symbolName: "sparkles.rectangle.stack",
                    payload: .createAgent(workspaceSelection: .none, agentName: "two", command: "two")
                )
            ],
            emptyMessage: "none"
        )
        store.commandBar.highlightedIndex = 1
        store.moveHighlightedCommand(1)
        XCTAssertEqual(store.commandBar.highlightedIndex, 0)
    }

    @MainActor
    func testUpdateCommandQueryResetsOutOfRangeHighlightToFirstVisibleResult() {
        let store = SpurwechselStore()
        store.openCommandBar()
        store.commandBar.highlightedIndex = 3

        store.updateCommandQuery("create")

        XCTAssertTrue(store.filteredCommands.contains(.createAgent))
        XCTAssertTrue(store.filteredCommands.contains(.createDefaultAgent))
        XCTAssertEqual(store.commandBar.highlightedIndex, 0)

        store.commandBar.mode = .picker(
            title: "Pick",
            items: [
                CommandBarPickerItem(
                    id: "alpha",
                    title: "alpha",
                    subtitle: "group a",
                    symbolName: "sparkles.rectangle.stack",
                    payload: .createAgent(workspaceSelection: .none, agentName: "alpha", command: "alpha")
                ),
                CommandBarPickerItem(
                    id: "beta",
                    title: "beta",
                    subtitle: "group b",
                    symbolName: "sparkles.rectangle.stack",
                    payload: .createAgent(workspaceSelection: .none, agentName: "beta", command: "beta")
                )
            ],
            emptyMessage: "none"
        )
        store.commandBar.highlightedIndex = 5
        store.updateCommandQuery("beta")

        XCTAssertEqual(store.filteredPickerItems.count, 1)
        XCTAssertEqual(store.commandBar.highlightedIndex, 0)
    }

    @MainActor
    func testConfiguredShortcutConsumesMatchingKeyEvent() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spurwechsel-shortcuts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let configStore = ProjectConfigStore(
            configURL: temporaryDirectory.appendingPathComponent("config.yaml")
        )
        try configStore.save(
            UserConfigFile.explicit(from: SpurwechselConfig(
                shortcuts: [
                    ShortcutRecord(
                        command: .toggleCommandBar,
                        key: "p",
                        modifiers: [.command]
                    )
                ]
            ))
        )

        let store = SpurwechselStore(configStore: configStore)
        XCTAssertEqual(
            store.shortcutBinding(for: .toggleCommandBar),
            ResolvedShortcutBinding(command: .toggleCommandBar, key: "p", modifiers: [.command])
        )

        let commandP = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command],
                timestamp: 1,
                windowNumber: 0,
                context: nil,
                characters: "p",
                charactersIgnoringModifiers: "p",
                isARepeat: false,
                keyCode: 35
            )
        )
        let commandK = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command],
                timestamp: 2,
                windowNumber: 0,
                context: nil,
                characters: "k",
                charactersIgnoringModifiers: "k",
                isARepeat: false,
                keyCode: 40
            )
        )

        XCTAssertTrue(store.handleGlobalShortcutEvent(commandP))
        XCTAssertTrue(store.commandBar.isPresented)

        store.closeCommandBar()
        XCTAssertFalse(store.handleGlobalShortcutEvent(commandK))
        XCTAssertFalse(store.commandBar.isPresented)
    }

    @MainActor
    func testDefaultShortcutConsumesCommandKWhenConfigOmitsShortcuts() throws {
        let store = SpurwechselStore()
        XCTAssertEqual(
            store.shortcutBinding(for: .toggleCommandBar),
            ResolvedShortcutBinding(command: .toggleCommandBar, key: "k", modifiers: [.command])
        )
        let commandK = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 3,
            windowNumber: 0,
            context: nil,
            characters: "k",
            charactersIgnoringModifiers: "k",
            isARepeat: false,
            keyCode: 40
        ))

        XCTAssertTrue(store.handleGlobalShortcutEvent(commandK))
        XCTAssertTrue(store.commandBar.isPresented)
    }

    @MainActor
    func testTerminalFocusedUnboundCommandKeyRewritesToControlWhenEnabled() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spurwechsel-terminal-shortcuts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let configStore = ProjectConfigStore(
            configURL: temporaryDirectory.appendingPathComponent("config.yaml")
        )
        try configStore.save(
            UserConfigFile.explicit(from: SpurwechselConfig(
                terminal: TerminalConfig(commandKeyMapsToControl: true)
            ))
        )

        let store = SpurwechselStore(configStore: configStore)
        store.selectMainView(.terminal)

        let commandU = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 3,
            windowNumber: 0,
            context: nil,
            characters: "u",
            charactersIgnoringModifiers: "u",
            isARepeat: false,
            keyCode: 32
        ))

        let result = store.handleKeyDownEvent(commandU, focusedSurfaceSlot: .main)
        switch result {
        case let .replace(replacement):
            XCTAssertTrue(replacement.modifierFlags.contains(.control))
            XCTAssertFalse(replacement.modifierFlags.contains(.command))
        case .passThrough, .consume:
            XCTFail("Expected replacement key event while terminal is focused")
        }
        XCTAssertFalse(store.commandBar.isPresented)
    }

    @MainActor
    func testTerminalFocusedBoundCommandShortcutStillConsumesWhenRemapEnabled() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spurwechsel-terminal-bound-shortcuts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let configStore = ProjectConfigStore(
            configURL: temporaryDirectory.appendingPathComponent("config.yaml")
        )
        try configStore.save(
            UserConfigFile.explicit(from: SpurwechselConfig(
                terminal: TerminalConfig(commandKeyMapsToControl: true)
            ))
        )

        let store = SpurwechselStore(configStore: configStore)
        store.selectMainView(.terminal)

        let commandK = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 4,
            windowNumber: 0,
            context: nil,
            characters: "k",
            charactersIgnoringModifiers: "k",
            isARepeat: false,
            keyCode: 40
        ))

        let result = store.handleKeyDownEvent(commandK, focusedSurfaceSlot: .main)
        switch result {
        case .consume:
            break
        case .passThrough, .replace:
            XCTFail("Expected command shortcut to be consumed while terminal is focused")
        }
        XCTAssertTrue(store.commandBar.isPresented)
    }

    @MainActor
    func testVSCodeFocusedCommandShortcutStillConsumesWhenRemapEnabled() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spurwechsel-vscode-shortcuts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let configStore = ProjectConfigStore(
            configURL: temporaryDirectory.appendingPathComponent("config.yaml")
        )
        try configStore.save(
            UserConfigFile.explicit(from: SpurwechselConfig(
                terminal: TerminalConfig(commandKeyMapsToControl: true)
            ))
        )

        let store = SpurwechselStore(configStore: configStore)
        store.selectMainView(.vscode)

        let commandK = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 5,
            windowNumber: 0,
            context: nil,
            characters: "k",
            charactersIgnoringModifiers: "k",
            isARepeat: false,
            keyCode: 40
        ))

        let result = store.handleKeyDownEvent(commandK, focusedSurfaceSlot: .main)
        switch result {
        case .consume:
            break
        case .passThrough, .replace:
            XCTFail("Expected command shortcut to be consumed while VSCode is focused")
        }
        XCTAssertTrue(store.commandBar.isPresented)
    }

    @MainActor
    func testCommandBarCloseDefaultsToFocusRestore() {
        let store = SpurwechselStore()

        store.openCommandBar()
        XCTAssertTrue(store.commandBar.isPresented)

        store.closeCommandBar()
        XCTAssertFalse(store.commandBar.isPresented)
        XCTAssertTrue(store.commandBarShouldRestorePreviousFocus)
    }

    @MainActor
    func testCommandExecutionClosesWithoutFocusRestore() {
        let store = SpurwechselStore()

        store.openCommandBar()
        store.executeCommand(.toggleLeftSidebar)

        XCTAssertFalse(store.commandBar.isPresented)
        XCTAssertFalse(store.commandBarShouldRestorePreviousFocus)
    }

    @MainActor
    func testQuitCommandAppearsInCommandPaletteSearch() {
        let store = SpurwechselStore()

        store.openCommandBar()
        XCTAssertTrue(store.filteredCommands.contains(.quit))

        store.updateCommandQuery("quit")

        XCTAssertTrue(store.filteredCommands.contains(.quit))
    }

    @MainActor
    func testRemoveProjectCommandAppearsInCommandPaletteSearch() {
        let store = SpurwechselStore()

        store.openCommandBar()
        XCTAssertTrue(store.filteredCommands.contains(.removeProject))

        store.updateCommandQuery("remove project")

        XCTAssertTrue(store.filteredCommands.contains(.removeProject))
    }

    @MainActor
    func testQuitCommandClosesCommandBarAndInvokesQuitHandler() {
        final class QuitSpy {
            var callCount = 0
        }

        let spy = QuitSpy()
        let store = SpurwechselStore(
            applicationQuitHandler: {
                spy.callCount += 1
            }
        )

        store.openCommandBar()
        store.executeCommand(.quit)

        XCTAssertFalse(store.commandBar.isPresented)
        XCTAssertFalse(store.commandBarShouldRestorePreviousFocus)
        XCTAssertEqual(spy.callCount, 1)
    }

    @MainActor
    func testStoreShowsConfigNotificationWhenStartupConfigIsInvalid() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spurwechsel-state-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let configURL = temporaryDirectory.appendingPathComponent("config.yaml")
        let yaml = """
        version: nope
        """
        try yaml.appending("\n").write(to: configURL, atomically: true, encoding: .utf8)

        let store = SpurwechselStore(configStore: ProjectConfigStore(configURL: configURL))

        XCTAssertEqual(store.configNotification?.title, "Config invalid")
        XCTAssertTrue(store.configNotification?.detailMessage?.contains("version must be an integer") == true)
    }

    @MainActor
    func testStoreStartsWithoutConfigNotificationWhenConfigIsValid() {
        let store = SpurwechselStore()

        XCTAssertNil(store.configNotification)
    }
}

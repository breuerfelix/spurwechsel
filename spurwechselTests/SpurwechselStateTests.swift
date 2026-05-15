import XCTest
@testable import spurwechsel

final class SpurwechselStateTests: XCTestCase {
    func testPreferredPreviewWidthStartsUnset() {
        let layout = AppLayoutState()
        XCTAssertNil(layout.preferredPreviewWidth)
    }

    func testPreferredLeftSidebarWidthStartsUnset() {
        let layout = AppLayoutState()
        XCTAssertNil(layout.preferredLeftSidebarWidth)
    }

    func testPreferredRightSidebarWidthStartsUnset() {
        let layout = AppLayoutState()
        XCTAssertNil(layout.preferredRightSidebarWidth)
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

    func testPreferredLeftSidebarWidthClampsToAllowedRange() {
        var layout = AppLayoutState()

        layout.setPreferredLeftSidebarWidth(200, allowedRange: 240...480)
        XCTAssertEqual(layout.preferredLeftSidebarWidth, 240)

        layout.setPreferredLeftSidebarWidth(312, allowedRange: 240...480)
        XCTAssertEqual(layout.preferredLeftSidebarWidth, 312)

        layout.setPreferredLeftSidebarWidth(900, allowedRange: 240...480)
        XCTAssertEqual(layout.preferredLeftSidebarWidth, 480)
    }

    func testPreferredRightSidebarWidthClampsToAllowedRange() {
        var layout = AppLayoutState()

        layout.setPreferredRightSidebarWidth(180, allowedRange: 220...420)
        XCTAssertEqual(layout.preferredRightSidebarWidth, 220)

        layout.setPreferredRightSidebarWidth(300, allowedRange: 220...420)
        XCTAssertEqual(layout.preferredRightSidebarWidth, 300)

        layout.setPreferredRightSidebarWidth(900, allowedRange: 220...420)
        XCTAssertEqual(layout.preferredRightSidebarWidth, 420)
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
    }

    func testProjectsStateRestoreCollapsedProjectsFromPersistedPathsAfterRefresh() {
        let firstProjectID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let refreshedProjectID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        let secondProjectID = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!
        let firstPath = "/tmp/project-one"

        let firstProject = Project(
            id: firstProjectID,
            name: "project-one",
            branch: "main",
            path: firstPath
        )
        let secondProject = Project(
            id: secondProjectID,
            name: "project-two",
            branch: "main",
            path: "/tmp/project-two"
        )
        var state = ProjectsState.fromImportedProjects(
            [firstProject, secondProject],
            collapsedProjectPaths: [firstPath]
        )

        XCTAssertTrue(state.collapsedProjectIDs.contains(firstProjectID))

        let refreshedFirstProject = Project(
            id: refreshedProjectID,
            name: "project-one",
            branch: "main",
            path: firstPath
        )
        state.replaceProjects(
            [refreshedFirstProject, secondProject],
            configuredSections: []
        )

        XCTAssertTrue(state.collapsedProjectPaths.contains(firstPath))
        XCTAssertTrue(state.collapsedProjectIDs.contains(refreshedProjectID))
        XCTAssertFalse(state.collapsedProjectIDs.contains(firstProjectID))
    }

    func testAgentStateAddAgentSelectsNewSession() {
        var state = PreviewFixtures.agentState

        let session = state.addAgent(
            to: .project(PreviewFixtures.tiltrunProject.id),
            launcherName: "codex",
            launchCommand: "codex",
            workingDirectory: "/tmp/tiltrun"
        )

        XCTAssertEqual(state.selectedSessionID, session.id)
        XCTAssertEqual(state.selectedSession?.workspaceSelection, .project(PreviewFixtures.tiltrunProject.id))
        XCTAssertEqual(state.selectedSession?.name, "codex-1")
        XCTAssertEqual(state.nextAgentCount, 2)
    }

    func testAgentStateRemoveSelectedSessionFallsBackToSiblingSession() {
        var state = AgentState(
            sessions: [],
            selectedSessionID: nil,
            nextAgentCount: 1
        )
        let selection = WorkspaceSelection.project(PreviewFixtures.tiltrunProject.id)
        let first = state.addAgent(
            to: selection,
            launcherName: "codex",
            launchCommand: "codex",
            workingDirectory: "/tmp/tiltrun"
        )
        let second = state.addAgent(
            to: selection,
            launcherName: "claude",
            launchCommand: "claude",
            workingDirectory: "/tmp/tiltrun"
        )

        XCTAssertEqual(state.selectedSessionID, second.id)

        state.removeSession(second.id)

        XCTAssertEqual(state.selectedSessionID, first.id)
        XCTAssertEqual(state.sessions.count, 1)
    }

    func testFilteredCommandsReturnsQuitForQuitQuery() {
        var commandBar = CommandBarState()
        commandBar.isPresented = true
        commandBar.query = "quit"
        let commands = CommandPaletteQuery.filteredCommands(
            commandBar: commandBar,
            projects: PreviewFixtures.projectsState
        )

        XCTAssertEqual(commands.first, .quit)
    }

    func testFilteredCommandsHideWorktreeCommandsWithoutGitRepository() {
        let projects = ProjectsState.fromImportedProjects([
            Project(
                id: UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!,
                name: "notes",
                branch: "",
                path: "/tmp/notes",
                isGitRepository: false
            )
        ])
        var commandBar = CommandBarState()
        commandBar.isPresented = true

        let commands = CommandPaletteQuery.visibleCommandsForCurrentContext(
            commandBar: commandBar,
            projects: projects
        )

        XCTAssertFalse(commands.contains(.addWorktree))
        XCTAssertFalse(commands.contains(.deleteWorktree))
    }

    func testFilteredCommandsShowWorktreeCommandsForGitRepository() {
        let projects = ProjectsState.fromImportedProjects([
            Project(
                id: UUID(uuidString: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")!,
                name: "repo",
                branch: "main",
                path: "/tmp/repo",
                isGitRepository: true
            )
        ])
        var commandBar = CommandBarState()
        commandBar.isPresented = true

        let commands = CommandPaletteQuery.visibleCommandsForCurrentContext(
            commandBar: commandBar,
            projects: projects
        )

        XCTAssertTrue(commands.contains(.addWorktree))
        XCTAssertTrue(commands.contains(.deleteWorktree))
    }

    func testFilteredPickerItemsSelectProjectPrioritizesTitleOverBranch() {
        let selectionA = WorkspaceSelection.project(UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!)
        let selectionB = WorkspaceSelection.project(UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!)
        let items = [
            CommandBarPickerItem(
                id: "workspace-a",
                title: "screeps-workbench",
                subtitle: "main",
                symbolName: "folder",
                payload: .selectWorkspace(selectionA),
                secondarySearchPenalty: 50
            ),
            CommandBarPickerItem(
                id: "workspace-b",
                title: "orbit",
                subtitle: "sw-feature",
                symbolName: "folder",
                payload: .selectWorkspace(selectionB),
                secondarySearchPenalty: 50
            )
        ]
        var commandBar = CommandBarState()
        commandBar.mode = .picker(title: "Select Project", items: items, emptyMessage: "")
        commandBar.query = "sw"

        let filtered = CommandPaletteQuery.filteredPickerItems(commandBar: commandBar)

        XCTAssertEqual(filtered.map(\.id), ["workspace-a", "workspace-b"])
    }

    func testFilteredPickerItemsKeepsBranchOnlyMatch() {
        let selection = WorkspaceSelection.project(UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!)
        let items = [
            CommandBarPickerItem(
                id: "workspace-a",
                title: "orbit",
                subtitle: "release/2026",
                symbolName: "folder",
                payload: .selectWorkspace(selection),
                secondarySearchPenalty: 50
            ),
            CommandBarPickerItem(
                id: "workspace-b",
                title: "tiltrun",
                subtitle: "main",
                symbolName: "folder",
                payload: .selectWorkspace(selection),
                secondarySearchPenalty: 50
            )
        ]
        var commandBar = CommandBarState()
        commandBar.mode = .picker(title: "Select Project", items: items, emptyMessage: "")
        commandBar.query = "release"

        let filtered = CommandPaletteQuery.filteredPickerItems(commandBar: commandBar)

        XCTAssertEqual(filtered.map(\.id), ["workspace-a"])
    }

    func testFilteredPickerItemsDefaultSecondaryWeightUnchanged() {
        let selectionA = WorkspaceSelection.project(UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!)
        let selectionB = WorkspaceSelection.project(UUID(uuidString: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")!)
        let items = [
            CommandBarPickerItem(
                id: "picker-a",
                title: "screeps-workbench",
                subtitle: "main",
                symbolName: "sparkles.rectangle.stack",
                payload: .selectWorkspace(selectionA)
            ),
            CommandBarPickerItem(
                id: "picker-b",
                title: "orbit",
                subtitle: "sw-feature",
                symbolName: "sparkles.rectangle.stack",
                payload: .selectWorkspace(selectionB)
            )
        ]
        var commandBar = CommandBarState()
        commandBar.mode = .picker(title: "Create Agent", items: items, emptyMessage: "")
        commandBar.query = "sw"

        let filtered = CommandPaletteQuery.filteredPickerItems(commandBar: commandBar)

        XCTAssertEqual(filtered.map(\.id), ["picker-b", "picker-a"])
    }
}

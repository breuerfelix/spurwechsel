import XCTest

final class spurwechselUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCommandKFiltersAddProjectAndImportsFolder() throws {
        let fixture = try makeFixture(
            existingProjectName: "existing-project",
            pendingImportName: "palette-project"
        )

        let app = XCUIApplication()
        app.launchEnvironment["SPURWECHSEL_CONFIG_PATH"] = fixture.configURL.path
        app.launchEnvironment["SPURWECHSEL_TEST_IMPORT_PATHS"] = fixture.importDirectory.path
        app.launchEnvironment["SPURWECHSEL_WORKTREES_ROOT"] = fixture.worktreesRoot.path
        app.launch()

        XCTAssertTrue(app.buttons["projects.project.existing-project"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["projects.project-branch.existing-project"].exists)

        app.typeKey("k", modifierFlags: [.command])
        XCTAssertTrue(app.otherElements["commandbar.overlay"].waitForExistence(timeout: 2))

        let searchField = app.textFields["commandbar.search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 2))
        searchField.tap()
        searchField.typeText("new prj")

        let addProjectOption = app.buttons["commandbar.option.add-new-project"]
        XCTAssertTrue(addProjectOption.waitForExistence(timeout: 2))

        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
        XCTAssertTrue(app.buttons["projects.project.palette-project"].waitForExistence(timeout: 2))

        let savedConfigText = try String(contentsOf: fixture.configURL, encoding: .utf8)
        XCTAssertTrue(savedConfigText.contains("palette-project"))
    }

    func testProjectPlusRunsAddWorktreeFlow() throws {
        let fixture = try makeFixture(existingProjectName: "existing-project")

        let app = XCUIApplication()
        app.launchEnvironment["SPURWECHSEL_CONFIG_PATH"] = fixture.configURL.path
        app.launchEnvironment["SPURWECHSEL_WORKTREES_ROOT"] = fixture.worktreesRoot.path
        app.launch()

        XCTAssertTrue(app.buttons["projects.project.existing-project"].waitForExistence(timeout: 2))
        let plusButton = app.buttons["projects.create-worktree.existing-project"]
        XCTAssertTrue(plusButton.waitForExistence(timeout: 2))
        plusButton.tap()

        let input = app.textFields["commandbar.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 2))
        input.tap()
        input.typeText("feature-ui")
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])

        XCTAssertTrue(app.buttons["projects.worktree.feature-ui"].waitForExistence(timeout: 3))

        let expectedWorktreePath = fixture.worktreesRoot
            .appendingPathComponent("existing-project", isDirectory: true)
            .appendingPathComponent("feature-ui", isDirectory: true)
            .path
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedWorktreePath))
    }

    func testDeleteWorktreeUsesPickerAndConfirmation() throws {
        let fixture = try makeFixture(
            existingProjectName: "existing-project",
            initialWorktreeName: "cleanup-me"
        )

        let app = XCUIApplication()
        app.launchEnvironment["SPURWECHSEL_CONFIG_PATH"] = fixture.configURL.path
        app.launchEnvironment["SPURWECHSEL_WORKTREES_ROOT"] = fixture.worktreesRoot.path
        app.launch()

        XCTAssertTrue(app.buttons["projects.worktree.cleanup-me"].waitForExistence(timeout: 3))

        app.typeKey("k", modifierFlags: [.command])
        let searchField = app.textFields["commandbar.search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 2))
        searchField.tap()
        searchField.typeText("delete work")
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])

        let pickerField = app.textFields["commandbar.search"]
        XCTAssertTrue(pickerField.waitForExistence(timeout: 2))
        pickerField.tap()
        pickerField.typeText("cleanup")
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])

        let confirmButton = app.buttons["commandbar.confirm"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 2))
        confirmButton.tap()

        XCTAssertFalse(app.buttons["projects.worktree.cleanup-me"].waitForExistence(timeout: 2))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.initialWorktreePath?.path ?? ""))
    }

    func testDeleteWorktreeConfirmationAcceptsReturnKey() throws {
        let fixture = try makeFixture(
            existingProjectName: "existing-project",
            initialWorktreeName: "cleanup-return"
        )

        let app = XCUIApplication()
        app.launchEnvironment["SPURWECHSEL_CONFIG_PATH"] = fixture.configURL.path
        app.launchEnvironment["SPURWECHSEL_WORKTREES_ROOT"] = fixture.worktreesRoot.path
        app.launch()

        XCTAssertTrue(app.buttons["projects.worktree.cleanup-return"].waitForExistence(timeout: 3))

        app.typeKey("k", modifierFlags: [.command])
        let searchField = app.textFields["commandbar.search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 2))
        searchField.tap()
        searchField.typeText("delete work")
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])

        let pickerField = app.textFields["commandbar.search"]
        XCTAssertTrue(pickerField.waitForExistence(timeout: 2))
        pickerField.tap()
        pickerField.typeText("cleanup-return")
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])

        XCTAssertTrue(app.buttons["commandbar.confirm"].waitForExistence(timeout: 2))
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])

        XCTAssertFalse(app.buttons["projects.worktree.cleanup-return"].waitForExistence(timeout: 2))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.initialWorktreePath?.path ?? ""))
    }

    func testCommandPaletteCreateAgentLaunchesSession() throws {
        let fixture = try makeFixture(existingProjectName: "existing-project")

        let app = XCUIApplication()
        app.launchEnvironment["SPURWECHSEL_CONFIG_PATH"] = fixture.configURL.path
        app.launchEnvironment["SPURWECHSEL_WORKTREES_ROOT"] = fixture.worktreesRoot.path
        app.launch()

        XCTAssertTrue(app.buttons["projects.project.existing-project"].waitForExistence(timeout: 2))

        app.typeKey("k", modifierFlags: [.command])
        let searchField = app.textFields["commandbar.search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 2))
        searchField.tap()
        searchField.typeText("create agent")
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])

        let pickerField = app.textFields["commandbar.search"]
        XCTAssertTrue(pickerField.waitForExistence(timeout: 2))
        pickerField.tap()
        pickerField.typeText("codex")
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])

        XCTAssertTrue(app.buttons["agents.session.codex-1"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.otherElements["agent.terminal"].waitForExistence(timeout: 2))
    }

    func testCommandPaletteCreateDefaultAgentLaunchesWithoutPicker() throws {
        let fixture = try makeFixture(existingProjectName: "existing-project")

        let app = XCUIApplication()
        app.launchEnvironment["SPURWECHSEL_CONFIG_PATH"] = fixture.configURL.path
        app.launchEnvironment["SPURWECHSEL_WORKTREES_ROOT"] = fixture.worktreesRoot.path
        app.launch()

        XCTAssertTrue(app.buttons["projects.project.existing-project"].waitForExistence(timeout: 2))

        app.typeKey("k", modifierFlags: [.command])
        let searchField = app.textFields["commandbar.search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 2))
        searchField.tap()
        searchField.typeText("create default agent")
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])

        XCTAssertTrue(app.buttons["agents.session.opencode-1"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.textFields["commandbar.search"].exists)
    }

    func testOpenCodeWithoutWarpPluginShowsTopBarWarningBadgeOnly() throws {
        let fixture = try makeFixture(existingProjectName: "existing-project")
        try writeOpenCodeConfig(plugins: [], in: fixture.repositoryDirectory)

        let app = XCUIApplication()
        app.launchEnvironment["SPURWECHSEL_CONFIG_PATH"] = fixture.configURL.path
        app.launchEnvironment["SPURWECHSEL_WORKTREES_ROOT"] = fixture.worktreesRoot.path
        app.launch()

        let addAgentButton = app.buttons["agents.add.existing-project"]
        XCTAssertTrue(addAgentButton.waitForExistence(timeout: 2))

        addAgentButton.tap()
        let pickerField = app.textFields["commandbar.search"]
        XCTAssertTrue(pickerField.waitForExistence(timeout: 2))
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
        XCTAssertTrue(app.buttons["agents.session.opencode-1"].waitForExistence(timeout: 2))

        let warningBadge = app.otherElements["agent.header.warp-warning.badge"]
        XCTAssertTrue(warningBadge.waitForExistence(timeout: 2))
        XCTAssertEqual(app.otherElements.matching(identifier: "agent.header.warp-warning.badge").count, 1)

        addAgentButton.tap()
        XCTAssertTrue(pickerField.waitForExistence(timeout: 2))
        pickerField.tap()
        pickerField.typeText("codex")
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
        XCTAssertTrue(app.buttons["agents.session.codex-2"].waitForExistence(timeout: 2))
        app.buttons["agents.session.codex-2"].tap()

        XCTAssertFalse(warningBadge.waitForExistence(timeout: 1))
    }

    func testCommandPaletteArrowDownSelectsNextCommand() throws {
        let fixture = try makeFixture(existingProjectName: "existing-project")

        let app = XCUIApplication()
        app.launchEnvironment["SPURWECHSEL_CONFIG_PATH"] = fixture.configURL.path
        app.launchEnvironment["SPURWECHSEL_WORKTREES_ROOT"] = fixture.worktreesRoot.path
        app.launch()

        XCTAssertTrue(app.buttons["projects.project.existing-project"].waitForExistence(timeout: 2))

        app.typeKey("k", modifierFlags: [.command])
        let searchField = app.textFields["commandbar.search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 2))
        searchField.tap()

        app.typeKey(XCUIKeyboardKey.downArrow, modifierFlags: [])
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])

        XCTAssertTrue(app.textFields["commandbar.input"].waitForExistence(timeout: 2))
    }

    func testCommandPalettePickerArrowDownSelectsSecondItem() throws {
        let fixture = try makeFixture(
            existingProjectName: "existing-project",
            initialWorktreeName: "cleanup-a"
        )

        let secondWorktreePath = fixture.worktreesRoot
            .appendingPathComponent("existing-project", isDirectory: true)
            .appendingPathComponent("cleanup-b", isDirectory: true)
        try FileManager.default.createDirectory(
            at: secondWorktreePath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try runGit(
            arguments: ["worktree", "add", "-b", "cleanup-b", secondWorktreePath.path, "main"],
            in: fixture.repositoryDirectory
        )

        let app = XCUIApplication()
        app.launchEnvironment["SPURWECHSEL_CONFIG_PATH"] = fixture.configURL.path
        app.launchEnvironment["SPURWECHSEL_WORKTREES_ROOT"] = fixture.worktreesRoot.path
        app.launch()

        XCTAssertTrue(app.buttons["projects.worktree.cleanup-a"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["projects.worktree.cleanup-b"].waitForExistence(timeout: 3))

        app.typeKey("k", modifierFlags: [.command])
        let searchField = app.textFields["commandbar.search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 2))
        searchField.tap()
        searchField.typeText("delete work")
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])

        let pickerField = app.textFields["commandbar.search"]
        XCTAssertTrue(pickerField.waitForExistence(timeout: 2))
        pickerField.tap()
        app.typeKey(XCUIKeyboardKey.downArrow, modifierFlags: [])
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])

        let confirmButton = app.buttons["commandbar.confirm"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 2))
        confirmButton.tap()

        XCTAssertTrue(app.buttons["projects.worktree.cleanup-a"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["projects.worktree.cleanup-b"].waitForExistence(timeout: 2))
    }

    func testAgentSidebarPlusRunsCreateAgentFlow() throws {
        let fixture = try makeFixture(existingProjectName: "existing-project")

        let app = XCUIApplication()
        app.launchEnvironment["SPURWECHSEL_CONFIG_PATH"] = fixture.configURL.path
        app.launchEnvironment["SPURWECHSEL_WORKTREES_ROOT"] = fixture.worktreesRoot.path
        app.launch()

        let addAgentButton = app.buttons["agents.add.existing-project"]
        XCTAssertTrue(addAgentButton.waitForExistence(timeout: 2))
        addAgentButton.tap()

        let pickerField = app.textFields["commandbar.search"]
        XCTAssertTrue(pickerField.waitForExistence(timeout: 2))
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])

        XCTAssertTrue(app.buttons["agents.session.opencode-1"].waitForExistence(timeout: 2))
    }

    func testDeleteAgentConfirmationCancelsWithEscapeKey() throws {
        let fixture = try makeFixture(existingProjectName: "existing-project")

        let app = XCUIApplication()
        app.launchEnvironment["SPURWECHSEL_CONFIG_PATH"] = fixture.configURL.path
        app.launchEnvironment["SPURWECHSEL_WORKTREES_ROOT"] = fixture.worktreesRoot.path
        app.launch()

        let addAgentButton = app.buttons["agents.add.existing-project"]
        XCTAssertTrue(addAgentButton.waitForExistence(timeout: 2))
        addAgentButton.tap()

        let pickerField = app.textFields["commandbar.search"]
        XCTAssertTrue(pickerField.waitForExistence(timeout: 2))
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
        XCTAssertTrue(app.buttons["agents.session.opencode-1"].waitForExistence(timeout: 2))

        app.typeKey("k", modifierFlags: [.command])
        let searchField = app.textFields["commandbar.search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 2))
        searchField.tap()
        searchField.typeText("delete agent")
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])

        XCTAssertTrue(app.buttons["commandbar.confirm"].waitForExistence(timeout: 2))
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])

        XCTAssertFalse(app.buttons["commandbar.confirm"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.buttons["agents.session.opencode-1"].exists)
    }

    func testSwitchingAgentRowsUpdatesMainSessionHeader() throws {
        let fixture = try makeFixture(existingProjectName: "existing-project")

        let app = XCUIApplication()
        app.launchEnvironment["SPURWECHSEL_CONFIG_PATH"] = fixture.configURL.path
        app.launchEnvironment["SPURWECHSEL_WORKTREES_ROOT"] = fixture.worktreesRoot.path
        app.launch()

        let addAgentButton = app.buttons["agents.add.existing-project"]
        XCTAssertTrue(addAgentButton.waitForExistence(timeout: 2))

        addAgentButton.tap()
        let pickerField = app.textFields["commandbar.search"]
        XCTAssertTrue(pickerField.waitForExistence(timeout: 2))
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
        XCTAssertTrue(app.buttons["agents.session.opencode-1"].waitForExistence(timeout: 2))

        addAgentButton.tap()
        XCTAssertTrue(pickerField.waitForExistence(timeout: 2))
        pickerField.tap()
        pickerField.typeText("codex")
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
        XCTAssertTrue(app.buttons["agents.session.codex-2"].waitForExistence(timeout: 2))

        let headerName = app.staticTexts["agent.header.session-name"]
        XCTAssertTrue(headerName.waitForExistence(timeout: 2))
        XCTAssertEqual(headerName.label, "codex-2")

        app.buttons["agents.session.opencode-1"].tap()
        XCTAssertEqual(headerName.label, "opencode-1")

        app.buttons["agents.session.codex-2"].tap()
        XCTAssertEqual(headerName.label, "codex-2")
    }

    func testCreateAgentPickerKeepsFocusAfterAgentSwitch() throws {
        let fixture = try makeFixture(existingProjectName: "existing-project")

        let app = XCUIApplication()
        app.launchEnvironment["SPURWECHSEL_CONFIG_PATH"] = fixture.configURL.path
        app.launchEnvironment["SPURWECHSEL_WORKTREES_ROOT"] = fixture.worktreesRoot.path
        app.launch()

        let addAgentButton = app.buttons["agents.add.existing-project"]
        XCTAssertTrue(addAgentButton.waitForExistence(timeout: 2))

        addAgentButton.tap()
        let pickerField = app.textFields["commandbar.search"]
        XCTAssertTrue(pickerField.waitForExistence(timeout: 2))
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
        XCTAssertTrue(app.buttons["agents.session.opencode-1"].waitForExistence(timeout: 2))

        addAgentButton.tap()
        XCTAssertTrue(pickerField.waitForExistence(timeout: 2))
        pickerField.tap()
        pickerField.typeText("codex")
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
        XCTAssertTrue(app.buttons["agents.session.codex-2"].waitForExistence(timeout: 2))

        app.buttons["agents.session.opencode-1"].tap()
        app.buttons["agents.session.codex-2"].tap()

        app.typeKey("k", modifierFlags: [.command])
        let searchField = app.textFields["commandbar.search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 2))
        searchField.tap()
        searchField.typeText("create agent")
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])

        XCTAssertTrue(pickerField.waitForExistence(timeout: 2))
        app.typeKey("c", modifierFlags: [])
        app.typeKey("o", modifierFlags: [])
        app.typeKey("d", modifierFlags: [])
        app.typeKey("e", modifierFlags: [])
        app.typeKey("x", modifierFlags: [])

        guard let query = pickerField.value as? String else {
            return XCTFail("Expected picker search field value")
        }
        XCTAssertTrue(query.lowercased().contains("codex"))

        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
        XCTAssertTrue(app.buttons["agents.session.codex-3"].waitForExistence(timeout: 2))
    }

    func testSidebarCreateAgentPickerKeepsFocusAfterAgentSwitch() throws {
        let fixture = try makeFixture(existingProjectName: "existing-project")

        let app = XCUIApplication()
        app.launchEnvironment["SPURWECHSEL_CONFIG_PATH"] = fixture.configURL.path
        app.launchEnvironment["SPURWECHSEL_WORKTREES_ROOT"] = fixture.worktreesRoot.path
        app.launch()

        let addAgentButton = app.buttons["agents.add.existing-project"]
        XCTAssertTrue(addAgentButton.waitForExistence(timeout: 2))

        addAgentButton.tap()
        let pickerField = app.textFields["commandbar.search"]
        XCTAssertTrue(pickerField.waitForExistence(timeout: 2))
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
        XCTAssertTrue(app.buttons["agents.session.opencode-1"].waitForExistence(timeout: 2))

        addAgentButton.tap()
        XCTAssertTrue(pickerField.waitForExistence(timeout: 2))
        pickerField.tap()
        pickerField.typeText("codex")
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
        XCTAssertTrue(app.buttons["agents.session.codex-2"].waitForExistence(timeout: 2))

        app.buttons["agents.session.opencode-1"].tap()
        app.buttons["agents.session.codex-2"].tap()

        addAgentButton.tap()
        XCTAssertTrue(pickerField.waitForExistence(timeout: 2))
        app.typeKey("c", modifierFlags: [])
        app.typeKey("o", modifierFlags: [])
        app.typeKey("d", modifierFlags: [])
        app.typeKey("e", modifierFlags: [])
        app.typeKey("x", modifierFlags: [])

        guard let query = pickerField.value as? String else {
            return XCTFail("Expected picker search field value")
        }
        XCTAssertTrue(query.lowercased().contains("codex"))

        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
        XCTAssertTrue(app.buttons["agents.session.codex-3"].waitForExistence(timeout: 2))
    }

    func testTerminalMainViewShowsTerminalSurfaceAndSwitchesWorkspace() throws {
        let fixture = try makeFixture(
            existingProjectName: "existing-project",
            initialWorktreeName: "feature-terminal"
        )

        let app = XCUIApplication()
        app.launchEnvironment["SPURWECHSEL_CONFIG_PATH"] = fixture.configURL.path
        app.launchEnvironment["SPURWECHSEL_WORKTREES_ROOT"] = fixture.worktreesRoot.path
        app.launch()

        XCTAssertTrue(app.buttons["projects.project.existing-project"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["projects.worktree.feature-terminal"].waitForExistence(timeout: 3))

        app.buttons["topbar.view.terminal"].tap()

        XCTAssertTrue(app.otherElements["project-terminal.surface"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Terminal lanes"].exists)

        app.buttons["projects.worktree.feature-terminal"].tap()
        XCTAssertTrue(app.otherElements["project-terminal.surface"].waitForExistence(timeout: 2))

        app.buttons["projects.project.existing-project"].tap()
        XCTAssertTrue(app.otherElements["project-terminal.surface"].waitForExistence(timeout: 2))
    }

    func testCommandShortcutOpensCommandBarWhenTerminalFocused() throws {
        let fixture = try makeFixture(existingProjectName: "existing-project")

        let app = XCUIApplication()
        app.launchEnvironment["SPURWECHSEL_CONFIG_PATH"] = fixture.configURL.path
        app.launchEnvironment["SPURWECHSEL_WORKTREES_ROOT"] = fixture.worktreesRoot.path
        app.launch()

        app.buttons["topbar.view.terminal"].tap()
        XCTAssertTrue(app.otherElements["project-terminal.surface"].waitForExistence(timeout: 2))

        app.typeKey("k", modifierFlags: [.command])
        XCTAssertTrue(app.otherElements["commandbar.overlay"].waitForExistence(timeout: 2))
    }

    func testCommandShortcutOpensCommandBarWhenVSCodeFocused() throws {
        let fixture = try makeFixture(existingProjectName: "existing-project")

        let app = XCUIApplication()
        app.launchEnvironment["SPURWECHSEL_CONFIG_PATH"] = fixture.configURL.path
        app.launchEnvironment["SPURWECHSEL_WORKTREES_ROOT"] = fixture.worktreesRoot.path
        app.launch()

        app.buttons["topbar.view.vscode"].tap()
        XCTAssertTrue(app.buttons["topbar.view.vscode"].exists)

        app.typeKey("k", modifierFlags: [.command])
        XCTAssertTrue(app.otherElements["commandbar.overlay"].waitForExistence(timeout: 2))
    }

    func testTopBarControlClicksAreImmediate() throws {
        let fixture = try makeFixture(existingProjectName: "existing-project")

        let app = XCUIApplication()
        app.launchEnvironment["SPURWECHSEL_CONFIG_PATH"] = fixture.configURL.path
        app.launchEnvironment["SPURWECHSEL_WORKTREES_ROOT"] = fixture.worktreesRoot.path
        app.launch()

        let projectRow = app.buttons["projects.project.existing-project"]
        XCTAssertTrue(projectRow.waitForExistence(timeout: 2))

        let commandBarButton = app.buttons["topbar.commandbar"]
        XCTAssertTrue(commandBarButton.waitForExistence(timeout: 2))
        let commandBarTapStartedAt = Date()
        commandBarButton.tap()
        XCTAssertTrue(
            app.otherElements["commandbar.overlay"].waitForExistence(timeout: 0.75),
            "Command bar should open on first click without double-click delay."
        )
        XCTAssertLessThan(Date().timeIntervalSince(commandBarTapStartedAt), 0.75)
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        XCTAssertFalse(app.otherElements["commandbar.overlay"].waitForExistence(timeout: 1))

        let rightSidebarButton = app.buttons["topbar.sidebar.right"]
        XCTAssertTrue(rightSidebarButton.waitForExistence(timeout: 2))

        let hideSidebarStartedAt = Date()
        rightSidebarButton.tap()
        let sidebarHiddenExpectation = expectation(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: projectRow
        )
        XCTAssertEqual(XCTWaiter.wait(for: [sidebarHiddenExpectation], timeout: 0.75), .completed)
        XCTAssertLessThan(Date().timeIntervalSince(hideSidebarStartedAt), 0.75)

        let showSidebarStartedAt = Date()
        rightSidebarButton.tap()
        XCTAssertTrue(projectRow.waitForExistence(timeout: 0.75))
        XCTAssertLessThan(Date().timeIntervalSince(showSidebarStartedAt), 0.75)
    }

    private func makeFixture(
        existingProjectName: String,
        pendingImportName: String? = nil,
        initialWorktreeName: String? = nil
    ) throws -> (
        configURL: URL,
        repositoryDirectory: URL,
        importDirectory: URL,
        worktreesRoot: URL,
        initialWorktreePath: URL?
    ) {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spurwechsel-ui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

        let repositoryDirectory = rootDirectory.appendingPathComponent(existingProjectName, isDirectory: true)
        try createGitRepository(at: repositoryDirectory)

        let importName = pendingImportName ?? "import-project"
        let importDirectory = rootDirectory.appendingPathComponent(importName, isDirectory: true)
        try createGitRepository(at: importDirectory)

        let worktreesRoot = rootDirectory.appendingPathComponent("worktrees", isDirectory: true)
        try FileManager.default.createDirectory(at: worktreesRoot, withIntermediateDirectories: true)

        var initialWorktreePath: URL?
        if let initialWorktreeName {
            let path = worktreesRoot
                .appendingPathComponent(existingProjectName, isDirectory: true)
                .appendingPathComponent(initialWorktreeName, isDirectory: true)
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try runGit(arguments: ["worktree", "add", "-b", initialWorktreeName, path.path, "main"], in: repositoryDirectory)
            initialWorktreePath = path
        }

        let configDirectory = rootDirectory.appendingPathComponent(".spurwechsel", isDirectory: true)
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        let configURL = configDirectory.appendingPathComponent("config.yaml")

        let yaml = """
        version: 1
        projects:
          - path: "\(repositoryDirectory.path)"
            name: "\(existingProjectName)"
        """
        try yaml.appending("\n").write(to: configURL, atomically: true, encoding: .utf8)

        return (configURL, repositoryDirectory, importDirectory, worktreesRoot, initialWorktreePath)
    }

    private func createGitRepository(at path: URL) throws {
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        try runGit(arguments: ["init", "--initial-branch", "main"], in: path)
        try runGit(arguments: ["config", "user.name", "Spurwechsel UI Tests"], in: path)
        try runGit(arguments: ["config", "user.email", "ui-tests@example.com"], in: path)
        let fileURL = path.appendingPathComponent("README.md")
        try "seed".write(to: fileURL, atomically: true, encoding: .utf8)
        try runGit(arguments: ["add", "README.md"], in: path)
        try runGit(arguments: ["commit", "-m", "seed"], in: path)
    }

    private func writeOpenCodeConfig(plugins: [String], in directory: URL) throws {
        let pluginsList = plugins.map { "\"\($0)\"" }.joined(separator: ", ")
        let payload = """
        {
          "plugin": [\(pluginsList)]
        }
        """
        let configURL = directory.appendingPathComponent("opencode.json")
        try payload.appending("\n").write(to: configURL, atomically: true, encoding: .utf8)
    }

    private func runGit(arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = directory

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderr = String(
                data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "git command failed"
            XCTFail(stderr)
            throw NSError(domain: "spurwechselUITests", code: Int(process.terminationStatus))
        }
    }
}

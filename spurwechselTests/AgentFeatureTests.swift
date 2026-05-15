import ComposableArchitecture
import XCTest
@testable import spurwechsel

@MainActor
final class AgentFeatureTests: XCTestCase {
    func testLaunchRequestedSetsWarpRichStatusWhenPluginInstalled() async {
        let selection = WorkspaceSelection.project(PreviewFixtures.tiltrunProject.id)
        let request = AgentLaunchRequest(
            workspaceSelection: selection,
            workingDirectory: "/tmp/repo",
            agentName: "opencode",
            command: "opencode",
            terminalTheme: ThemeSet.default.terminalTheme
        )

        let store = TestStore(initialState: AgentFeature.State(agents: AgentState(
            sessions: [],
            selectedSessionID: nil,
            nextAgentCount: 1
        ))) {
            AgentFeature()
        } withDependencies: { dependencies in
            dependencies.openCodeConfigClient.isWarpPluginInstalled = { _ in true }
            dependencies.terminalRegistryClient.acquireAgentController = { _, _, _, _, _, _, _, _ in }
            dependencies.terminalRegistryClient.releaseAgentController = { _ in }
            dependencies.terminalRegistryClient.setAgentAttached = { _, _ in }
            dependencies.terminalRegistryClient.setWorkspaceAttached = { _, _ in }
            dependencies.terminalRegistryClient.ensureWorkspaceController = { _, _, _ in }
            dependencies.terminalRegistryClient.shutdownAll = { _, _ in
                TerminalRegistryShutdownSummary(sessionCount: 0, forcedKillCount: 0, timedOutCount: 0)
            }
        }

        await store.send(.launchRequested(request)) {
            XCTAssertEqual($0.agents.sessions.count, 1)
            XCTAssertEqual($0.agents.selectedSession?.workspaceSelection, selection)
            XCTAssertEqual($0.agents.selectedSession?.status, .idle)
            XCTAssertTrue($0.agents.selectedSession?.expectsRichStatus ?? false)
            XCTAssertEqual($0.agents.nextAgentCount, 2)
        }

        let launchedID = try XCTUnwrap(store.state.agents.selectedSession?.id)
        await store.receive(.delegate(.sessionLaunched(sessionID: launchedID, workspaceSelection: selection)))
    }
}

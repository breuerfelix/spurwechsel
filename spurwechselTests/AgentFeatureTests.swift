import ComposableArchitecture
import XCTest
@testable import spurwechsel

@MainActor
final class AgentFeatureTests: XCTestCase {
    func testLaunchRequestedSetsWarpRichStatusWhenPluginInstalled() async throws {
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
            dependencies.agentRuntimeClient.buildLaunchPlan = { _, command, _, _ in
                AgentRuntimeLaunchPlan(
                    startupTitle: command,
                    runtimeCommand: command,
                    expectsRichStatus: true
                )
            }
            dependencies.agentRuntimeClient.start = { _, _, _, _ in
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.launchRequested(request))

        XCTAssertEqual(store.state.agents.sessions.count, 1)
        XCTAssertEqual(store.state.agents.selectedSessionID, store.state.agents.sessions[0].id)
        XCTAssertEqual(store.state.agents.sessions[0].workspaceSelection, selection)
        XCTAssertEqual(store.state.agents.sessions[0].kind, .opencode)
        XCTAssertEqual(store.state.agents.sessions[0].status, .idle)
        XCTAssertEqual(store.state.agents.sessions[0].launcherName, "opencode")
        XCTAssertEqual(store.state.agents.sessions[0].launchCommand, "opencode")
        XCTAssertEqual(store.state.agents.sessions[0].workingDirectory, "/tmp/repo")
        XCTAssertEqual(store.state.agents.sessions[0].terminalTitle, "opencode")
        XCTAssertTrue(store.state.agents.sessions[0].expectsRichStatus)
        XCTAssertEqual(store.state.agents.nextAgentCount, 2)

        let launchedID = store.state.agents.sessions[0].id
        await store.receive {
            guard case let .delegate(.sessionLaunched(sessionID, workspaceSelection)) = $0 else {
                return false
            }
            return sessionID == launchedID && workspaceSelection == selection
        }
    }
}

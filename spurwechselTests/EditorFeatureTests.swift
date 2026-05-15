import ComposableArchitecture
import XCTest
@testable import spurwechsel

@MainActor
final class EditorFeatureTests: XCTestCase {
    func testRuntimeStartingEventSetsSessionStatus() async throws {
        let workspaceID = PreviewFixtures.projectsState.selection.stableID
        let workspacePath = "/tmp/repo"
        let serverURL = try XCTUnwrap(URL(string: "http://127.0.0.1:19001/"))

        let store = TestStore(initialState: EditorFeature.State(
            sessionsByWorkspaceID: [:],
            selectedWorkspaceID: nil,
            vscodeMountedWorkspaceIDs: []
        )) {
            EditorFeature()
        }

        await store.send(.runtimeEvent(
            workspaceID: workspaceID,
            event: .starting(
                workspaceID: workspaceID,
                workspacePath: workspacePath,
                serverURL: serverURL
            )
        )) {
            $0.selectedWorkspaceID = workspaceID
            $0.sessionsByWorkspaceID[workspaceID] = EditorSessionState(
                workspaceSelectionID: workspaceID,
                workspaceName: nil,
                workspacePath: workspacePath,
                serverAddress: serverURL.absoluteString,
                workspaceAddress: nil,
                status: .starting,
                statusMessage: "Starting code-server for selected workspace at 127.0.0.1:19001…",
                errorMessage: nil,
                lastOutputLine: nil,
                browserPhase: .loading
            )
            $0.vscodeMountedWorkspaceIDs = [workspaceID]
        }
    }
}

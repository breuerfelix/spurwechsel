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

        await store.send(.runtimeEvent(.starting(
            workspaceID: workspaceID,
            workspacePath: workspacePath,
            serverURL: serverURL
        ))) {
            $0.selectedWorkspaceID = workspaceID
            let session = $0.sessionsByWorkspaceID[workspaceID]
            XCTAssertEqual(session?.workspacePath, workspacePath)
            XCTAssertEqual(session?.serverAddress, serverURL.absoluteString)
            XCTAssertEqual(session?.status, .starting)
        }
    }
}

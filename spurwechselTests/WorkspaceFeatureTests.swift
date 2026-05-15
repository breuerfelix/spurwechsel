import ComposableArchitecture
import XCTest
@testable import spurwechsel

@MainActor
final class WorkspaceFeatureTests: XCTestCase {
    func testSelectWorkspaceUpdatesSelectionAndDelegates() async {
        let targetSelection = WorkspaceSelection.project(PreviewFixtures.orbitProject.id)
        let store = TestStore(initialState: WorkspaceFeature.State(projects: PreviewFixtures.projectsState)) {
            WorkspaceFeature()
        }

        await store.send(.selectWorkspace(targetSelection)) {
            $0.projects.select(targetSelection)
        }

        await store.receive(.delegate(.selectionChanged(targetSelection)))
    }

    func testToggleProjectCollapseMutatesState() async {
        let store = TestStore(initialState: WorkspaceFeature.State(projects: PreviewFixtures.projectsState)) {
            WorkspaceFeature()
        }
        let projectID = PreviewFixtures.draftframeProject.id

        await store.send(.toggleProjectCollapse(projectID)) {
            $0.projects.toggleProjectCollapse(projectID)
        }
    }
}

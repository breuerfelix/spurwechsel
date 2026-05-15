import ComposableArchitecture
import XCTest
@testable import spurwechsel

@MainActor
final class WorkbenchFeatureTests: XCTestCase {
    func testSelectSurfaceTabUpdatesSelection() async {
        let selection = PreviewFixtures.projectsState.selection
        let firstTab = SurfaceTab(
            id: .workspaceTerminal(selection.stableID),
            title: "Terminal",
            workspaceSelection: selection,
            sessionID: nil
        )
        let secondTab = SurfaceTab(
            id: .vscodeWorkspace(selection.stableID),
            title: "VSCode",
            workspaceSelection: selection,
            sessionID: nil
        )

        let store = TestStore(initialState: WorkbenchFeature.State(
            surfaceTabs: SurfaceTabState(
                tabs: [firstTab, secondTab],
                selectedTabID: firstTab.id
            ),
            surfaceMountState: SurfaceMountState(),
            nextSurfaceFocusRequestID: 0
        )) {
            WorkbenchFeature()
        }

        await store.send(.selectSurfaceTab(secondTab.id)) {
            $0.surfaceTabs.selectedTabID = secondTab.id
        }
    }
}

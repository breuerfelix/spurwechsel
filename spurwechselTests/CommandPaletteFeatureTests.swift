import ComposableArchitecture
import XCTest
@testable import spurwechsel

@MainActor
final class CommandPaletteFeatureTests: XCTestCase {
    func testSubmitCommandDelegatesExecuteCommand() async {
        let initialState = CommandPaletteFeature.State(
            commandBar: CommandBarState(
                isPresented: true,
                query: "",
                highlightedIndex: 0,
                mode: .commandList,
                notice: nil,
                textInput: "",
                projectContextID: nil,
                workspaceContext: nil
            )
        )

        let store = TestStore(initialState: initialState) {
            CommandPaletteFeature()
        }

        await store.send(.submit(filteredCommands: [.openAgentView], filteredPickerItems: []))
        await store.receive(.delegate(.executeCommand(
            .openAgentView,
            projectContextID: nil,
            workspaceContext: nil
        )))
    }
}

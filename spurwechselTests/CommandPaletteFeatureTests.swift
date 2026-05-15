import ComposableArchitecture
import XCTest
@testable import spurwechsel

@MainActor
final class CommandPaletteFeatureTests: XCTestCase {
    func testSubmitCommandDelegatesExecuteCommand() async {
        let initialState = CommandPaletteFeature.State(
            commandBar: CommandBarState(
                isPresented: true,
                mode: .commandList,
                query: "",
                textInput: "",
                highlightedIndex: 0,
                projectContextID: nil,
                workspaceContext: nil
            )
        )

        let store = TestStore(initialState: initialState) {
            CommandPaletteFeature()
        }

        await store.send(.submit(filteredCommands: [.openAgentView], filteredPickerItems: []))
        await store.receive { action in
            guard case let .delegate(.executeCommand(command, projectContextID, workspaceContext)) = action else {
                return false
            }
            return command == .openAgentView
                && projectContextID == nil
                && workspaceContext == nil
        }
    }
}

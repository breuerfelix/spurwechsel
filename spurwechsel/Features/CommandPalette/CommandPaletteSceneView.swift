import ComposableArchitecture
import SwiftUI

struct CommandPaletteSceneView: View {
    let shellStore: StoreOf<ShellFeature>
    let store: StoreOf<CommandPaletteFeature>
    let projects: ProjectsState
    let theme: SpurTheme
    let shortcutBinding: (CommandID) -> ResolvedShortcutBinding?

    var body: some View {
        let commandBar = store.state.commandBar
        let filteredCommands = CommandPaletteQuery.filteredCommands(
            commandBar: commandBar,
            projects: projects
        )
        let filteredPickerItems = CommandPaletteQuery.filteredPickerItems(commandBar: commandBar)

        if commandBar.isPresented {
            CommandPaletteOverlayView(
                commandBar: commandBar,
                filteredCommands: filteredCommands,
                filteredPickerItems: filteredPickerItems,
                theme: theme,
                shortcutBinding: shortcutBinding,
                closeCommandBar: closeCommandBar(restorePreviousFocus:),
                moveHighlightedCommand: { offset in
                    moveHighlightedCommand(
                        offset,
                        mode: commandBar.mode,
                        filteredCommands: filteredCommands,
                        filteredPickerItems: filteredPickerItems
                    )
                },
                executeCommand: executeCommand(_:),
                setHighlightedCommandIndex: { store.send(.setHighlightedIndex($0)) },
                updateCommandTextInput: { store.send(.updateTextInput($0)) },
                submitCommandBar: {
                    store.send(.submit(
                        filteredCommands: filteredCommands,
                        filteredPickerItems: filteredPickerItems
                    ))
                },
                updateCommandQuery: { store.send(.updateQuery($0)) }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.99)))
            .zIndex(5)
        }
    }

    private func closeCommandBar(restorePreviousFocus: Bool = true) {
        shellStore.send(.setCommandBarFocusRestore(restorePreviousFocus))
        store.send(.close(restorePreviousFocus: restorePreviousFocus))
    }

    private func moveHighlightedCommand(
        _ offset: Int,
        mode: CommandBarMode,
        filteredCommands: [CommandID],
        filteredPickerItems: [CommandBarPickerItem]
    ) {
        let itemCount: Int
        switch mode {
        case .commandList:
            itemCount = filteredCommands.count
        case .picker:
            itemCount = filteredPickerItems.count
        case .textInput, .confirmation:
            itemCount = 0
        }

        store.send(.moveHighlighted(offset: offset, itemCount: itemCount))
    }

    private func executeCommand(_ command: CommandID) {
        let commandBar = store.state.commandBar
        store.send(.executeCommand(
            command,
            projectContextID: commandBar.projectContextID,
            workspaceContext: commandBar.workspaceContext
        ))
    }
}

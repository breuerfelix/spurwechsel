import ComposableArchitecture
import Foundation

struct CommandPaletteFeature: Reducer {
    @ObservableState
    struct State: Equatable {
        var commandBar: CommandBarState
    }

    enum Action {
        enum Delegate: Equatable {
            case executeCommand(CommandID, projectContextID: UUID?, workspaceContext: WorkspaceSelection?)
            case submitConfirmation(CommandBarConfirmationPrompt)
            case submitPickerItem(CommandBarPickerItem)
            case submitTextInput(CommandBarTextPrompt)
        }

        case open(projectContextID: UUID?, workspaceContext: WorkspaceSelection?)
        case close(restorePreviousFocus: Bool)
        case executeCommand(CommandID, projectContextID: UUID?, workspaceContext: WorkspaceSelection?)
        case moveHighlighted(offset: Int, itemCount: Int)
        case presentConfirmation(CommandBarConfirmationPrompt, projectContextID: UUID?, workspaceContext: WorkspaceSelection?)
        case presentError(String, projectContextID: UUID?, workspaceContext: WorkspaceSelection?, ensurePresented: Bool)
        case presentPicker(title: String, items: [CommandBarPickerItem], emptyMessage: String, projectContextID: UUID?, workspaceContext: WorkspaceSelection?)
        case presentTextInput(CommandBarTextPrompt, projectContextID: UUID?, workspaceContext: WorkspaceSelection?)
        case setNotice(CommandBarNotice?)
        case setHighlightedIndex(Int)
        case submit(filteredCommands: [CommandID], filteredPickerItems: [CommandBarPickerItem])
        case togglePresentation
        case updateQuery(String)
        case updateTextInput(String)
        case setCommandBar(CommandBarState)
        case delegate(Delegate)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .open(projectContextID, workspaceContext):
                state.commandBar.presentCommandList(
                    projectContextID: projectContextID,
                    workspaceContext: workspaceContext
                )
                return .none
            case .close:
                state.commandBar.close()
                return .none
            case .executeCommand:
                guard case let .executeCommand(command, projectContextID, workspaceContext) = action else {
                    return .none
                }
                return .send(.delegate(.executeCommand(
                    command,
                    projectContextID: projectContextID,
                    workspaceContext: workspaceContext
                )))
            case let .moveHighlighted(offset, itemCount):
                guard itemCount > 0 else {
                    state.commandBar.highlightedIndex = 0
                    return .none
                }

                let currentIndex = min(state.commandBar.highlightedIndex, itemCount - 1)
                let nextIndex = (currentIndex + offset + itemCount) % itemCount
                state.commandBar.highlightedIndex = nextIndex
                return .none
            case let .presentConfirmation(prompt, projectContextID, workspaceContext):
                state.commandBar.presentConfirmation(
                    prompt,
                    projectContextID: projectContextID,
                    workspaceContext: workspaceContext
                )
                return .none
            case let .presentError(text, projectContextID, workspaceContext, ensurePresented):
                state.commandBar.presentError(
                    text,
                    projectContextID: projectContextID,
                    workspaceContext: workspaceContext,
                    ensurePresented: ensurePresented
                )
                return .none
            case let .presentPicker(title, items, emptyMessage, projectContextID, workspaceContext):
                state.commandBar.presentPicker(
                    title: title,
                    items: items,
                    emptyMessage: emptyMessage,
                    projectContextID: projectContextID,
                    workspaceContext: workspaceContext
                )
                return .none
            case let .presentTextInput(prompt, projectContextID, workspaceContext):
                state.commandBar.presentTextInput(
                    prompt,
                    projectContextID: projectContextID,
                    workspaceContext: workspaceContext
                )
                return .none
            case let .setNotice(notice):
                state.commandBar.notice = notice
                return .none
            case let .setHighlightedIndex(index):
                state.commandBar.highlightedIndex = max(0, index)
                return .none
            case .submit:
                switch state.commandBar.mode {
                case .commandList:
                    guard case let .submit(filteredCommands, _) = action,
                          !filteredCommands.isEmpty else {
                        return .none
                    }
                    let selectedIndex = min(
                        state.commandBar.highlightedIndex,
                        filteredCommands.count - 1
                    )
                    let command = filteredCommands[selectedIndex]
                    return .send(.delegate(.executeCommand(
                        command,
                        projectContextID: state.commandBar.projectContextID,
                        workspaceContext: state.commandBar.workspaceContext
                    )))
                case let .textInput(prompt):
                    return .send(.delegate(.submitTextInput(prompt)))
                case .picker:
                    guard case let .submit(_, filteredPickerItems) = action,
                          !filteredPickerItems.isEmpty else {
                        return .none
                    }
                    let selectedIndex = min(
                        state.commandBar.highlightedIndex,
                        filteredPickerItems.count - 1
                    )
                    return .send(.delegate(.submitPickerItem(filteredPickerItems[selectedIndex])))
                case let .confirmation(prompt):
                    return .send(.delegate(.submitConfirmation(prompt)))
                }
            case .togglePresentation:
                state.commandBar.isPresented
                    ? state.commandBar.close()
                    : state.commandBar.presentCommandList()
                return .none
            case let .updateQuery(query):
                state.commandBar.query = query
                state.commandBar.highlightedIndex = 0
                return .none
            case let .updateTextInput(text):
                state.commandBar.textInput = text
                return .none
            case let .setCommandBar(commandBar):
                state.commandBar = commandBar
                return .none
            case .delegate:
                return .none
            }
        }
    }
}

import SwiftUI

enum CommandPaletteOverlayMetrics {
    static let topPadding: CGFloat = 100
    static let bottomMargin: CGFloat = 200
    static let paletteWidth: CGFloat = 620
    static let headerHeight: CGFloat = 58
    static let dividerHeight: CGFloat = 1
    static let noticeReserve: CGFloat = 44
    static let estimatedRowHeight: CGFloat = 66
}

struct CommandPaletteOverlayView: View {
    let commandBar: CommandBarState
    let filteredCommands: [CommandID]
    let filteredPickerItems: [CommandBarPickerItem]
    let theme: SpurTheme
    let shortcutBinding: (CommandID) -> ResolvedShortcutBinding?
    let closeCommandBar: (Bool) -> Void
    let moveHighlightedCommand: (Int) -> Void
    let executeCommand: (CommandID) -> Void
    let setHighlightedCommandIndex: (Int) -> Void
    let updateCommandTextInput: (String) -> Void
    let submitCommandBar: () -> Void
    let updateCommandQuery: (String) -> Void

    @FocusState private var focusedField: CommandPaletteFocusField?
    @State private var searchFieldShouldFocus = false
    @State private var searchFieldFocusRequestID = 0
    @State private var confirmationFocusRequestID = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                theme.overlay
                    .ignoresSafeArea()
                    .onTapGesture {
                        closeCommandBar(true)
                    }

                VStack(spacing: 0) {
                    paletteCard(maxHeight: paletteMaxHeight(in: geometry.size.height))
                }
                .padding(.top, CommandPaletteOverlayMetrics.topPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .onAppear {
            scheduleFocusForCurrentMode()
        }
        .onChange(of: commandBar.mode) {
            scheduleFocusForCurrentMode()
        }
        .onExitCommand {
            handleExitCommand()
        }
        .onMoveCommand { direction in
            switch direction {
            case .down:
                moveHighlightedCommand(1)
            case .up:
                moveHighlightedCommand(-1)
            default:
                break
            }
        }
        .accessibilityIdentifier("commandbar.overlay")
    }

    private func paletteCard(maxHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            switch commandBar.mode {
            case .commandList:
                CommandPaletteCommandListView(
                    commandBar: commandBar,
                    filteredCommands: filteredCommands,
                    theme: theme,
                    shortcutBinding: shortcutBinding,
                    searchFieldShouldFocus: searchFieldShouldFocus,
                    searchFieldFocusRequestID: searchFieldFocusRequestID,
                    maxHeight: resultsRegionMaxHeight(within: maxHeight),
                    moveHighlightedCommand: moveHighlightedCommand,
                    executeCommand: executeCommand,
                    updateCommandQuery: updateCommandQuery,
                    submitCommandBar: submitCommandBar
                )
            case let .textInput(prompt):
                CommandPaletteTextInputPanel(
                    commandBar: commandBar,
                    prompt: prompt,
                    theme: theme,
                    focusedField: $focusedField,
                    updateCommandTextInput: updateCommandTextInput,
                    submitCommandBar: submitCommandBar,
                    closeCommandBar: closeCommandBar
                )
            case let .picker(title, _, emptyMessage):
                CommandPalettePickerListView(
                    commandBar: commandBar,
                    title: title,
                    emptyMessage: emptyMessage,
                    filteredPickerItems: filteredPickerItems,
                    theme: theme,
                    searchFieldShouldFocus: searchFieldShouldFocus,
                    searchFieldFocusRequestID: searchFieldFocusRequestID,
                    maxHeight: resultsRegionMaxHeight(within: maxHeight),
                    moveHighlightedCommand: moveHighlightedCommand,
                    setHighlightedIndex: setHighlightedCommandIndex,
                    updateCommandQuery: updateCommandQuery,
                    submitCommandBar: submitCommandBar
                )
            case let .confirmation(prompt):
                CommandPaletteConfirmationPanel(
                    commandBar: commandBar,
                    prompt: prompt,
                    theme: theme,
                    confirmationFocusRequestID: confirmationFocusRequestID,
                    submitCommandBar: submitCommandBar,
                    closeCommandBar: closeCommandBar
                )
            }
        }
        .id(modeIdentity)
        .frame(width: CommandPaletteOverlayMetrics.paletteWidth)
        .background(theme.panelRaised)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(theme.borderStrong, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: theme.shadow, radius: 14, x: 0, y: 8)
        .accessibilityIdentifier("commandbar.palette")
    }

    private func focusForCurrentMode() {
        switch commandBar.mode {
        case .textInput:
            focusedField = .input
            searchFieldShouldFocus = false
        case .confirmation:
            focusedField = nil
            searchFieldShouldFocus = false
            confirmationFocusRequestID += 1
        case .commandList, .picker:
            focusedField = nil
            searchFieldShouldFocus = true
            searchFieldFocusRequestID += 1
        }
    }

    private func scheduleFocusForCurrentMode() {
        DispatchQueue.main.async {
            focusForCurrentMode()
        }
    }

    private func handleExitCommand() {
        closeCommandBar(true)
    }

    private func paletteMaxHeight(in availableHeight: CGFloat) -> CGFloat {
        max(
            0,
            availableHeight
                - CommandPaletteOverlayMetrics.topPadding
                - CommandPaletteOverlayMetrics.bottomMargin
        )
    }

    private func resultsRegionMaxHeight(within paletteMaxHeight: CGFloat) -> CGFloat {
        let noticeReserve = commandBar.notice == nil ? 0 : CommandPaletteOverlayMetrics.noticeReserve
        return max(
            0,
            paletteMaxHeight
                - CommandPaletteOverlayMetrics.headerHeight
                - CommandPaletteOverlayMetrics.dividerHeight
                - noticeReserve
        )
    }

    private var modeIdentity: String {
        switch commandBar.mode {
        case .commandList:
            return "command-list"
        case let .textInput(prompt):
            return "text-input-\(prompt.title)-\(prompt.placeholder)-\(prompt.submitTitle)"
        case let .picker(title, items, emptyMessage):
            return "picker-\(title)-\(items.count)-\(emptyMessage)"
        case let .confirmation(prompt):
            return "confirmation-\(prompt.title)-\(prompt.message)-\(prompt.confirmTitle)"
        }
    }
}

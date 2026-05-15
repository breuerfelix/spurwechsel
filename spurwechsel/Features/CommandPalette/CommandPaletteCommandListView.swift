import SwiftUI

struct CommandPaletteCommandListView: View {
    let commandBar: CommandBarState
    let filteredCommands: [CommandID]
    let theme: SpurTheme
    let shortcutBinding: (CommandID) -> ResolvedShortcutBinding?
    let searchFieldShouldFocus: Bool
    let searchFieldFocusRequestID: Int
    let maxHeight: CGFloat
    let moveHighlightedCommand: (Int) -> Void
    let executeCommand: (CommandID) -> Void
    let updateCommandQuery: (String) -> Void
    let submitCommandBar: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CommandPaletteSearchHeaderView(
                query: commandBar.query,
                placeholder: "Type command",
                isFocused: searchFieldShouldFocus,
                focusRequestID: searchFieldFocusRequestID,
                theme: theme,
                onSubmit: submitCommandBar,
                onMoveUp: { moveHighlightedCommand(-1) },
                onMoveDown: { moveHighlightedCommand(1) },
                onQueryChange: updateCommandQuery
            )

            Divider()
                .background(theme.border)

            if filteredCommands.isEmpty {
                CommandPaletteEmptyStateView(text: "No command matches.", theme: theme)
            } else {
                commandResultsView
            }

            if let notice = commandBar.notice {
                CommandPaletteNoticeView(notice: notice, theme: theme)
            }
        }
    }

    @ViewBuilder
    private var commandResultsView: some View {
        if resultsContentHeight <= maxHeight {
            commandResultsContent
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    commandResultsContent
                }
                .autoHidingOverlayScrollIndicators()
                .frame(height: maxHeight)
                .onAppear {
                    scrollToHighlightedIndex(in: proxy)
                }
                .onChange(of: commandBar.highlightedIndex) { _, _ in
                    scrollToHighlightedIndex(in: proxy)
                }
            }
        }
    }

    private var commandResultsContent: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(filteredCommands.enumerated()), id: \.offset) { index, command in
                Button {
                    executeCommand(command)
                } label: {
                    CommandPaletteResultRow(
                        title: command.title,
                        subtitle: command.keywords.joined(separator: "  "),
                        symbolName: command.symbolName,
                        trailingShortcut: shortcutBinding(command)?.displayLabel,
                        isSelected: index == commandBar.highlightedIndex,
                        theme: theme
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .id(index)
                .accessibilityIdentifier("commandbar.option.\(command.accessibilityID)")
            }
        }
    }

    private var resultsContentHeight: CGFloat {
        CGFloat(filteredCommands.count) * CommandPaletteOverlayMetrics.estimatedRowHeight
    }

    private func scrollToHighlightedIndex(in proxy: ScrollViewProxy) {
        guard !filteredCommands.isEmpty else {
            return
        }

        let targetIndex = min(commandBar.highlightedIndex, filteredCommands.count - 1)
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.12)) {
                proxy.scrollTo(targetIndex, anchor: .center)
            }
        }
    }
}

import SwiftUI

struct CommandPalettePickerListView: View {
    let commandBar: CommandBarState
    let title: String
    let emptyMessage: String
    let filteredPickerItems: [CommandBarPickerItem]
    let theme: SpurTheme
    let searchFieldShouldFocus: Bool
    let maxHeight: CGFloat
    let moveHighlightedCommand: (Int) -> Void
    let setHighlightedIndex: (Int) -> Void
    let updateCommandQuery: (String) -> Void
    let submitCommandBar: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CommandPaletteSearchHeaderView(
                query: commandBar.query,
                placeholder: title,
                isFocused: searchFieldShouldFocus,
                theme: theme,
                onSubmit: submitCommandBar,
                onMoveUp: { moveHighlightedCommand(-1) },
                onMoveDown: { moveHighlightedCommand(1) },
                onQueryChange: updateCommandQuery
            )

            Divider()
                .background(theme.border)

            if filteredPickerItems.isEmpty {
                CommandPaletteEmptyStateView(text: emptyMessage, theme: theme)
            } else {
                pickerResultsView
            }

            if let notice = commandBar.notice {
                CommandPaletteNoticeView(notice: notice, theme: theme)
            }
        }
    }

    @ViewBuilder
    private var pickerResultsView: some View {
        if resultsContentHeight <= maxHeight {
            pickerResultsContent
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    pickerResultsContent
                }
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

    private var pickerResultsContent: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(filteredPickerItems.enumerated()), id: \.offset) { index, item in
                Button {
                    setHighlightedIndex(index)
                    submitCommandBar()
                } label: {
                    CommandPaletteResultRow(
                        title: item.title,
                        subtitle: item.subtitle,
                        symbolName: item.symbolName,
                        trailingShortcut: nil,
                        isSelected: index == commandBar.highlightedIndex,
                        theme: theme
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .id(index)
                .accessibilityIdentifier("commandbar.pick.\(item.id.accessibilitySlug)")
            }
        }
    }

    private var resultsContentHeight: CGFloat {
        CGFloat(filteredPickerItems.count) * CommandPaletteOverlayMetrics.estimatedRowHeight
    }

    private func scrollToHighlightedIndex(in proxy: ScrollViewProxy) {
        guard !filteredPickerItems.isEmpty else {
            return
        }

        let targetIndex = min(commandBar.highlightedIndex, filteredPickerItems.count - 1)
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.12)) {
                proxy.scrollTo(targetIndex, anchor: .center)
            }
        }
    }
}
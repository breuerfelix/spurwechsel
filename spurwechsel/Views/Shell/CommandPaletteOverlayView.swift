import AppKit
import SwiftUI

struct CommandPaletteOverlayView: View {
    @ObservedObject var store: CommandPaletteViewStore

    private enum FocusField: Hashable {
        case input
    }

    private enum Metrics {
        static let topPadding: CGFloat = 100
        static let bottomMargin: CGFloat = 200
        static let paletteWidth: CGFloat = 620
        static let headerHeight: CGFloat = 58
        static let dividerHeight: CGFloat = 1
        static let noticeReserve: CGFloat = 44
        static let estimatedRowHeight: CGFloat = 66
    }

    @FocusState private var focusedField: FocusField?
    @State private var searchFieldShouldFocus = false

    private var theme: SpurTheme { store.theme }
    private var filteredCommands: [CommandID] { store.filteredCommands }
    private var filteredPickerItems: [CommandBarPickerItem] { store.filteredPickerItems }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                theme.overlay
                    .ignoresSafeArea()
                    .onTapGesture {
                        store.closeCommandBar()
                    }

                VStack(spacing: 0) {
                    paletteCard(maxHeight: paletteMaxHeight(in: geometry.size.height))
                }
                .padding(.top, Metrics.topPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .onAppear {
            scheduleFocusForCurrentMode()
        }
        .onChange(of: store.commandBar.mode) {
            scheduleFocusForCurrentMode()
        }
        .onExitCommand {
            handleExitCommand()
        }
        .onMoveCommand { direction in
            switch direction {
            case .down:
                store.moveHighlightedCommand(1)
            case .up:
                store.moveHighlightedCommand(-1)
            default:
                break
            }
        }
        .accessibilityIdentifier("commandbar.overlay")
    }

    private func paletteCard(maxHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            switch store.commandBar.mode {
            case .commandList:
                commandListView(maxHeight: maxHeight)
            case let .textInput(prompt):
                textInputView(prompt: prompt)
            case let .picker(title, _, emptyMessage):
                pickerView(title: title, emptyMessage: emptyMessage, maxHeight: maxHeight)
            case let .confirmation(prompt):
                confirmationView(prompt: prompt)
            }
        }
        .id(modeIdentity)
        .frame(width: Metrics.paletteWidth)
        .background(theme.panelRaised)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(theme.borderStrong, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: theme.shadow, radius: 14, x: 0, y: 8)
        .accessibilityIdentifier("commandbar.palette")
    }

    private func commandListView(maxHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            searchHeader(placeholder: "Type command")

            Divider()
                .background(theme.border)

            if filteredCommands.isEmpty {
                emptyStateText("No command matches.")
            } else {
                commandResultsView(maxHeight: resultsRegionMaxHeight(within: maxHeight))
            }

            if let notice = store.commandBar.notice {
                noticeView(notice)
            }
        }
    }

    private func textInputView(prompt: CommandBarTextPrompt) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(prompt.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.foregroundMuted)
                    .accessibilityIdentifier("commandbar.prompt")

                TextField(
                    prompt.placeholder,
                    text: Binding(
                        get: { store.commandBar.textInput },
                        set: { store.updateCommandTextInput($0) }
                    )
                )
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(theme.foreground)
                .focused($focusedField, equals: .input)
                .onSubmit {
                    store.submitCommandBar()
                }
                .accessibilityIdentifier("commandbar.input")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(theme.panel)

            Divider()
                .background(theme.border)

            HStack(spacing: 10) {
                Button(prompt.submitTitle) {
                    store.submitCommandBar()
                }
                .buttonStyle(CommandPalettePrimaryButtonStyle(theme: theme))
                .accessibilityIdentifier("commandbar.submit")

                Button("Cancel") {
                    store.closeCommandBar()
                }
                .buttonStyle(CommandPaletteSecondaryButtonStyle(theme: theme))
                .accessibilityIdentifier("commandbar.cancel")
            }
            .padding(16)

            if let notice = store.commandBar.notice {
                noticeView(notice)
            }
        }
    }

    private func pickerView(title: String, emptyMessage: String, maxHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            searchHeader(placeholder: title)

            Divider()
                .background(theme.border)

            if filteredPickerItems.isEmpty {
                emptyStateText(emptyMessage)
            } else {
                pickerResultsView(maxHeight: resultsRegionMaxHeight(within: maxHeight))
            }

            if let notice = store.commandBar.notice {
                noticeView(notice)
            }
        }
    }

    private func confirmationView(prompt: CommandBarConfirmationPrompt) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(prompt.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.foreground)
                Text(prompt.message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.foregroundMuted)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.panel)

            Divider()
                .background(theme.border)

            HStack(spacing: 10) {
                Button(prompt.confirmTitle) {
                    store.confirmCommandBarAction()
                }
                .buttonStyle(CommandPalettePrimaryButtonStyle(theme: theme))
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("commandbar.confirm")

                Button("Cancel") {
                    store.cancelCommandBarConfirmation()
                }
                .buttonStyle(CommandPaletteSecondaryButtonStyle(theme: theme))
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("commandbar.cancel")
            }
            .padding(16)

            if let notice = store.commandBar.notice {
                noticeView(notice)
            }
        }
    }

    private func searchHeader(placeholder: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.foregroundDim)
            CommandBarSearchField(
                text: Binding(
                    get: { store.commandBar.query },
                    set: { store.updateCommandQuery($0) }
                ),
                placeholder: placeholder,
                isFocused: searchFieldShouldFocus,
                onSubmit: {
                    store.submitCommandBar()
                },
                onMoveUp: {
                    store.moveHighlightedCommand(-1)
                },
                onMoveDown: {
                    store.moveHighlightedCommand(1)
                }
            )
            .frame(maxWidth: .infinity)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(theme.foreground)
            .accessibilityIdentifier("commandbar.search")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(theme.panel)
    }

    @ViewBuilder
    private func commandResultsView(maxHeight: CGFloat) -> some View {
        if resultsContentHeight(itemCount: filteredCommands.count) <= maxHeight {
            commandResultsContent()
        } else {
            scrollableCommandList(maxHeight: maxHeight)
        }
    }

    private func scrollableCommandList(maxHeight: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                commandResultsContent()
            }
            .frame(height: maxHeight)
            .onAppear {
                scrollToHighlightedIndex(store.commandBar.highlightedIndex, itemCount: filteredCommands.count, in: proxy)
            }
            .onChange(of: store.commandBar.highlightedIndex) { _, newValue in
                scrollToHighlightedIndex(newValue, itemCount: filteredCommands.count, in: proxy)
            }
        }
    }

    @ViewBuilder
    private func commandResultsContent() -> some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(filteredCommands.enumerated()), id: \.offset) { index, command in
                Button {
                    store.executeCommand(command, projectContextID: store.commandBar.projectContextID)
                } label: {
                    rowLabel(
                        title: command.title,
                        subtitle: command.keywords.joined(separator: "  "),
                        symbolName: command.symbolName,
                        trailingShortcut: store.shortcutBinding(for: command)?.displayLabel,
                        isSelected: index == store.commandBar.highlightedIndex
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

    @ViewBuilder
    private func pickerResultsView(maxHeight: CGFloat) -> some View {
        if resultsContentHeight(itemCount: filteredPickerItems.count) <= maxHeight {
            pickerResultsContent()
        } else {
            scrollablePickerList(maxHeight: maxHeight)
        }
    }

    private func scrollablePickerList(maxHeight: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                pickerResultsContent()
            }
            .frame(height: maxHeight)
            .onAppear {
                scrollToHighlightedIndex(store.commandBar.highlightedIndex, itemCount: filteredPickerItems.count, in: proxy)
            }
            .onChange(of: store.commandBar.highlightedIndex) { _, newValue in
                scrollToHighlightedIndex(newValue, itemCount: filteredPickerItems.count, in: proxy)
            }
        }
    }

    @ViewBuilder
    private func pickerResultsContent() -> some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(filteredPickerItems.enumerated()), id: \.offset) { index, item in
                Button {
                    store.commandBar.highlightedIndex = index
                    store.submitCommandBar()
                } label: {
                    rowLabel(
                        title: item.title,
                        subtitle: item.subtitle,
                        symbolName: item.symbolName,
                        trailingShortcut: nil,
                        isSelected: index == store.commandBar.highlightedIndex
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

    private func rowLabel(
        title: String,
        subtitle: String,
        symbolName: String,
        trailingShortcut: String?,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? theme.foreground : theme.foregroundMuted)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? theme.foreground : theme.foregroundMuted)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.foregroundDim)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if let trailingShortcut {
                shortcutBadge(
                    trailingShortcut,
                    isSelected: isSelected
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? theme.selection : Color.clear)
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func shortcutBadge(_ label: String, isSelected: Bool) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(isSelected ? theme.foreground : theme.foregroundDim)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(theme.panelRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            )
    }

    private func emptyStateText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(theme.foregroundDim)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func noticeView(_ notice: CommandBarNotice) -> some View {
        Text(notice.text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(notice.isError ? theme.error : theme.foregroundMuted)
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
            .accessibilityIdentifier("commandbar.notice")
    }

    private func focusForCurrentMode() {
        switch store.commandBar.mode {
        case .textInput:
            focusedField = .input
            searchFieldShouldFocus = false
        case .confirmation:
            focusedField = nil
            searchFieldShouldFocus = false
        case .commandList, .picker:
            focusedField = nil
            searchFieldShouldFocus = true
        }
    }

    private func scheduleFocusForCurrentMode() {
        DispatchQueue.main.async {
            focusForCurrentMode()
        }
    }

    private func handleExitCommand() {
        switch store.commandBar.mode {
        case .confirmation:
            store.cancelCommandBarConfirmation()
        default:
            store.closeCommandBar()
        }
    }

    private func paletteMaxHeight(in availableHeight: CGFloat) -> CGFloat {
        max(0, availableHeight - Metrics.topPadding - Metrics.bottomMargin)
    }

    private func resultsRegionMaxHeight(within paletteMaxHeight: CGFloat) -> CGFloat {
        let noticeReserve = store.commandBar.notice == nil ? 0 : Metrics.noticeReserve
        return max(0, paletteMaxHeight - Metrics.headerHeight - Metrics.dividerHeight - noticeReserve)
    }

    private func resultsContentHeight(itemCount: Int) -> CGFloat {
        CGFloat(itemCount) * Metrics.estimatedRowHeight
    }

    private func scrollToHighlightedIndex(
        _ highlightedIndex: Int,
        itemCount: Int,
        in proxy: ScrollViewProxy
    ) {
        guard itemCount > 0 else {
            return
        }

        let targetIndex = min(highlightedIndex, itemCount - 1)
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.12)) {
                proxy.scrollTo(targetIndex, anchor: .center)
            }
        }
    }

    private var modeIdentity: String {
        switch store.commandBar.mode {
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

private struct CommandPalettePrimaryButtonStyle: ButtonStyle {
    let theme: SpurTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(theme.accentForeground)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.accent.opacity(configuration.isPressed ? 0.82 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.accent.opacity(0.9), lineWidth: 1)
            )
    }
}

private struct CommandPaletteSecondaryButtonStyle: ButtonStyle {
    let theme: SpurTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(theme.foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.panelMuted.opacity(configuration.isPressed ? 0.88 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            )
    }
}

private struct CommandBarSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let isFocused: Bool
    let onSubmit: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.isBezeled = false
        field.font = .systemFont(ofSize: 16, weight: .medium)
        field.placeholderString = placeholder
        field.stringValue = text
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.delegate = context.coordinator
        field.setAccessibilityIdentifier("commandbar.search")
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
        }
        context.coordinator.parent = self
        nsView.setAccessibilityIdentifier("commandbar.search")

        guard let window = nsView.window else {
            return
        }

        if isFocused {
            if window.firstResponder !== nsView.currentEditor() {
                window.makeFirstResponder(nsView)
            }
        } else if window.firstResponder === nsView.currentEditor() {
            window.makeFirstResponder(nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CommandBarSearchField

        init(parent: CommandBarSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else {
                return
            }
            if parent.text != textField.stringValue {
                parent.text = textField.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                parent.onMoveUp()
                return true
            }
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                parent.onMoveDown()
                return true
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}

import SwiftUI

enum CommandPaletteFocusField: Hashable {
    case input
}

struct CommandPaletteTextInputPanel: View {
    let commandBar: CommandBarState
    let prompt: CommandBarTextPrompt
    let theme: SpurTheme
    let focusedField: FocusState<CommandPaletteFocusField?>.Binding
    let updateCommandTextInput: (String) -> Void
    let submitCommandBar: () -> Void
    let closeCommandBar: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(prompt.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.foregroundMuted)
                    .accessibilityIdentifier("commandbar.prompt")

                TextField(
                    prompt.placeholder,
                    text: Binding(
                        get: { commandBar.textInput },
                        set: { updateCommandTextInput($0) }
                    )
                )
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(theme.foreground)
                .focused(focusedField, equals: .input)
                .onSubmit {
                    submitCommandBar()
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
                    submitCommandBar()
                }
                .buttonStyle(CommandPalettePrimaryButtonStyle(theme: theme))
                .accessibilityIdentifier("commandbar.submit")

                Button("Cancel") {
                    closeCommandBar(true)
                }
                .buttonStyle(CommandPaletteSecondaryButtonStyle(theme: theme))
                .accessibilityIdentifier("commandbar.cancel")
            }
            .padding(16)

            if let notice = commandBar.notice {
                CommandPaletteNoticeView(notice: notice, theme: theme)
            }
        }
    }
}

struct CommandPaletteConfirmationPanel: View {
    let commandBar: CommandBarState
    let prompt: CommandBarConfirmationPrompt
    let theme: SpurTheme
    let confirmationFocusRequestID: Int
    let submitCommandBar: () -> Void
    let closeCommandBar: (Bool) -> Void

    var body: some View {
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
                    submitCommandBar()
                }
                .buttonStyle(CommandPalettePrimaryButtonStyle(theme: theme))
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("commandbar.confirm")

                Button("Cancel") {
                    closeCommandBar(true)
                }
                .buttonStyle(CommandPaletteSecondaryButtonStyle(theme: theme))
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("commandbar.cancel")
            }
            .padding(16)

            if let notice = commandBar.notice {
                CommandPaletteNoticeView(notice: notice, theme: theme)
            }
        }
        .background(
            CommandPaletteConfirmationKeyCapture(
                focusRequestID: confirmationFocusRequestID,
                onConfirm: submitCommandBar,
                onCancel: { closeCommandBar(true) }
            )
            .frame(width: 0, height: 0)
        )
    }
}

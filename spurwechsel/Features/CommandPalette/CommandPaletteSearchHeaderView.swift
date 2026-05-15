import SwiftUI

struct CommandPaletteSearchHeaderView: View {
    let query: String
    let placeholder: String
    let isFocused: Bool
    let focusRequestID: Int
    let theme: SpurTheme
    let onSubmit: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onQueryChange: (String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.foregroundDim)

            CommandBarSearchField(
                text: Binding(
                    get: { query },
                    set: { onQueryChange($0) }
                ),
                placeholder: placeholder,
                isFocused: isFocused,
                focusRequestID: focusRequestID,
                onSubmit: onSubmit,
                onMoveUp: onMoveUp,
                onMoveDown: onMoveDown
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
}

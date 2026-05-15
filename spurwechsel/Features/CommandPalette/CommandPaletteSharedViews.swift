import SwiftUI

struct CommandPaletteResultRow: View {
    let title: String
    let subtitle: String
    let symbolName: String
    let trailingShortcut: String?
    let isSelected: Bool
    let theme: SpurTheme

    var body: some View {
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
                CommandPaletteShortcutBadge(
                    label: trailingShortcut,
                    isSelected: isSelected,
                    theme: theme
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
}

struct CommandPaletteShortcutBadge: View {
    let label: String
    let isSelected: Bool
    let theme: SpurTheme

    var body: some View {
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
}

struct CommandPaletteEmptyStateView: View {
    let text: String
    let theme: SpurTheme

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(theme.foregroundDim)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CommandPaletteNoticeView: View {
    let notice: CommandBarNotice
    let theme: SpurTheme

    var body: some View {
        Text(notice.text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(notice.isError ? theme.error : theme.foregroundMuted)
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
            .accessibilityIdentifier("commandbar.notice")
    }
}
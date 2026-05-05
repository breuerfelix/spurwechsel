import SwiftUI

struct ChromeIconButton: View {
    let systemName: String
    let title: String
    let theme: SpurTheme
    let isSelected: Bool
    var showsSelection: Bool = true
    var accessibilityID: String?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(resolvedIconColor)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: SpurRadius.control, style: .continuous)
                        .fill(buttonFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SpurRadius.control, style: .continuous)
                        .stroke(theme.border, lineWidth: showsSelection && isSelected ? 0 : 1)
                )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .contentShape(RoundedRectangle(cornerRadius: SpurRadius.control, style: .continuous))
        .help(title)
        .onHover { hovering in
            isHovering = hovering
        }
        .accessibilityIdentifier(accessibilityID ?? title.lowercased())
    }

    private var buttonFill: Color {
        if showsSelection && isSelected {
            return theme.selection
        }
        if isHovering {
            return theme.panelRaised
        }
        return theme.panelMuted
    }

    private var resolvedIconColor: Color {
        if showsSelection && isSelected {
            return theme.foreground
        }
        if isHovering {
            return theme.foreground
        }
        return theme.foregroundMuted
    }
}

struct GhostActionButton: View {
    let systemName: String
    let title: String
    let theme: SpurTheme
    var buttonSize: CGFloat = 26
    var iconSize: CGFloat = 12
    var cornerRadius: CGFloat = 8
    var accessibilityID: String? = nil
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(isHovering ? theme.foreground : theme.foregroundMuted)
                .frame(width: buttonSize, height: buttonSize)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(isHovering ? theme.panelRaised : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(theme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(title)
        .onHover { hovering in
            isHovering = hovering
        }
        .accessibilityIdentifier(accessibilityID ?? title.lowercased())
    }
}

struct HitboxIconButton: View {
    let systemName: String
    let title: String
    let theme: SpurTheme
    var hitboxSize: CGFloat = 32
    var iconSize: CGFloat = 12
    var accessibilityID: String? = nil
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(isHovering ? theme.foreground : theme.foregroundMuted)
                .frame(width: hitboxSize, height: hitboxSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .onHover { hovering in
            isHovering = hovering
        }
        .accessibilityIdentifier(accessibilityID ?? title.lowercased())
    }
}

struct StatusBadgeView: View {
    let status: AgentSessionStatus
    let theme: SpurTheme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: status.symbolName)
                .font(.system(size: 12, weight: .semibold))
            Text(status.title)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(theme.statusColor(for: status))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(theme.statusColor(for: status).opacity(0.12))
        .overlay(
            Capsule()
                .stroke(theme.statusColor(for: status).opacity(0.32), lineWidth: 1)
        )
        .clipShape(Capsule())
    }
}

struct SurfaceStateView: View {
    enum Emphasis {
        case neutral
        case info
        case warning
        case error
    }

    let icon: String
    let title: String
    let message: String
    let theme: SpurTheme
    var emphasis: Emphasis = .info
    var actionHint: String? = nil
    var showsPanel: Bool = false

    var body: some View {
        VStack(spacing: SpurSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(iconColor)
            Text(title)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(theme.foreground)
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.foregroundMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            if let actionHint, !actionHint.isEmpty {
                Text(actionHint)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.foregroundDim)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(theme.panelMuted)
                    .clipShape(Capsule())
            }
        }
        .padding(SpurSpacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(SurfaceStateChromeModifier(theme: theme, showsPanel: showsPanel))
    }

    private var iconColor: Color {
        theme.accent
    }
}

private struct SurfaceStateChromeModifier: ViewModifier {
    let theme: SpurTheme
    let showsPanel: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if showsPanel {
            content
                .padding(SpurSpacing.xl)
                .spurPanel(theme: theme, fill: theme.panel, stroke: theme.border, shadowOpacity: 0.22)
        } else {
            content
        }
    }
}

struct ThemeToggleView: View {
    let theme: SpurTheme
    let selectedMode: ThemeMode
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: selectedMode.symbolName)
                Text(selectedMode.title)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(theme.foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(theme.panelMuted)
            .overlay(
                Capsule()
                    .stroke(theme.border, lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("theme.toggle")
    }
}

extension String {
    var accessibilitySlug: String {
        lowercased()
            .replacingOccurrences(of: ".", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
    }
}

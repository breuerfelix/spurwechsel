import GhosttyTerminal
import SwiftUI

struct SpurTheme {
    let background: Color
    let backgroundSecondary: Color
    let panel: Color
    let panelRaised: Color
    let panelMuted: Color
    let border: Color
    let borderStrong: Color
    let foreground: Color
    let foregroundMuted: Color
    let foregroundDim: Color
    let accent: Color
    let accentForeground: Color
    let selection: Color
    let terminal: Color
    let terminalForeground: Color
    let success: Color
    let warning: Color
    let error: Color
    let info: Color
    let overlay: Color
    let overlayStrong: Color
    let shadow: Color

    var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [background, backgroundSecondary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    func statusColor(for status: AgentSessionStatus) -> Color {
        switch status {
        case .launching:
            return warning
        case .idle:
            return info
        case .running:
            return success
        case .waitingApproval, .waitingInput:
            return warning
        case .exited:
            return foregroundMuted
        case .failed:
            return error
        }
    }
}

extension ThemeSet {
    func spurTheme(for mode: ThemeMode) -> SpurTheme {
        SpurTheme(palette: palette(for: mode))
    }

    var terminalTheme: TerminalTheme {
        TerminalTheme(
            light: terminalConfiguration(from: light),
            dark: terminalConfiguration(from: dark)
        )
    }

    private func terminalConfiguration(from palette: ThemePalette) -> TerminalConfiguration {
        TerminalConfiguration { builder in
            builder.withBackground(palette[.terminal].rgbHexWithoutHash)
            builder.withForeground(palette[.terminalForeground].rgbHexWithoutHash)
        }
    }
}

private extension SpurTheme {
    init(palette: ThemePalette) {
        background = Color(themeColor: palette[.background])
        backgroundSecondary = Color(themeColor: palette[.backgroundSecondary])
        panel = Color(themeColor: palette[.panel])
        panelRaised = Color(themeColor: palette[.panelRaised])
        panelMuted = Color(themeColor: palette[.panelMuted])
        border = Color(themeColor: palette[.border])
        borderStrong = Color(themeColor: palette[.borderStrong])
        foreground = Color(themeColor: palette[.foreground])
        foregroundMuted = Color(themeColor: palette[.foregroundMuted])
        foregroundDim = Color(themeColor: palette[.foregroundDim])
        accent = Color(themeColor: palette[.accent])
        accentForeground = Color(themeColor: palette[.accentForeground])
        selection = Color(themeColor: palette[.selection])
        terminal = Color(themeColor: palette[.terminal])
        terminalForeground = Color(themeColor: palette[.terminalForeground])
        success = Color(themeColor: palette[.success])
        warning = Color(themeColor: palette[.warning])
        error = Color(themeColor: palette[.error])
        info = Color(themeColor: palette[.info])
        overlay = Color(themeColor: palette[.overlay])
        overlayStrong = Color(themeColor: palette[.overlayStrong])
        shadow = Color(themeColor: palette[.shadow])
    }
}

extension ThemeMode {
    var colorScheme: ColorScheme {
        switch self {
        case .dark:
            return .dark
        case .light:
            return .light
        }
    }
}

enum SpurSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
}

enum SpurRadius {
    static let control: CGFloat = 10
    static let card: CGFloat = 14
    static let panel: CGFloat = 18
    static let shell: CGFloat = 24
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    init(hexString: String) {
        let normalized = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = normalized.hasPrefix("#") ? String(normalized.dropFirst()) : normalized
        let fallback = Color(hex: 0xFF00FF)
        guard payload.count == 6 || payload.count == 8,
              let parsed = UInt64(payload, radix: 16) else {
            self = fallback
            return
        }

        if payload.count == 6 {
            self.init(
                .sRGB,
                red: Double((parsed >> 16) & 0xFF) / 255,
                green: Double((parsed >> 8) & 0xFF) / 255,
                blue: Double(parsed & 0xFF) / 255,
                opacity: 1
            )
        } else {
            self.init(
                .sRGB,
                red: Double((parsed >> 24) & 0xFF) / 255,
                green: Double((parsed >> 16) & 0xFF) / 255,
                blue: Double((parsed >> 8) & 0xFF) / 255,
                opacity: Double(parsed & 0xFF) / 255
            )
        }
    }

    init(themeColor: ThemeColor) {
        self.init(hexString: themeColor.hex)
    }
}

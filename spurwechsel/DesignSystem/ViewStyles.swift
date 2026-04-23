import SwiftUI

struct SpurPanelModifier: ViewModifier {
    let theme: SpurTheme
    var fill: Color?
    var stroke: Color?
    var radius: CGFloat
    var shadowOpacity: Double

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill ?? theme.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(stroke ?? theme.border, lineWidth: 1)
            )
            .shadow(color: theme.shadow.opacity(shadowOpacity), radius: 24, y: 12)
    }
}

extension View {
    func spurPanel(
        theme: SpurTheme,
        fill: Color? = nil,
        stroke: Color? = nil,
        radius: CGFloat = SpurRadius.panel,
        shadowOpacity: Double = 0.35
    ) -> some View {
        modifier(
            SpurPanelModifier(
                theme: theme,
                fill: fill,
                stroke: stroke,
                radius: radius,
                shadowOpacity: shadowOpacity
            )
        )
    }
}

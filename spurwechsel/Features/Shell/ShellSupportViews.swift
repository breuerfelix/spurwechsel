import AppKit
import SwiftUI

struct HorizontalResizeCursorModifier: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                guard hovering != isHovering else { return }
                isHovering = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onDisappear {
                guard isHovering else { return }
                isHovering = false
                NSCursor.pop()
            }
    }
}

struct AppShutdownOverlayView: View {
    let state: LifecycleFeature.ShutdownPresentationState
    let theme: SpurTheme

    var body: some View {
        ZStack {
            Rectangle()
                .fill(theme.overlayStrong)
                .ignoresSafeArea()

            VStack(spacing: SpurSpacing.md) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.2)

                VStack(spacing: SpurSpacing.xs) {
                    Text(state.statusMessage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.foreground)
                        .multilineTextAlignment(.center)

                    Text(state.detailMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.foregroundMuted)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.panelRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(theme.borderStrong, lineWidth: 1)
            )
        }
    }
}

struct ConfigNotificationBannerView: View {
    let state: ConfigNotificationState
    let theme: SpurTheme
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: SpurSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.warning)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: SpurSpacing.xs) {
                Text(state.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.foreground)

                Text(state.message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.foregroundMuted)
                    .fixedSize(horizontal: false, vertical: true)

                if let detailMessage = state.detailMessage {
                    Text(detailMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.foregroundDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: SpurSpacing.md)

            GhostActionButton(
                systemName: "xmark",
                title: "Dismiss config warning",
                theme: theme,
                buttonSize: 24,
                iconSize: 10,
                cornerRadius: 7,
                accessibilityID: "config-warning.dismiss",
                action: dismiss
            )
        }
        .padding(.horizontal, SpurSpacing.md)
        .padding(.vertical, SpurSpacing.sm)
        .frame(maxWidth: 520, alignment: .leading)
        .spurPanel(
            theme: theme,
            fill: theme.panelRaised,
            stroke: theme.border,
            shadowOpacity: 0.2
        )
    }
}

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

private struct AutoHidingOverlayScrollIndicatorsModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            AutoHidingOverlayScrollIndicatorsConfigurator()
                .frame(width: 0, height: 0)
        )
    }
}

private struct AutoHidingOverlayScrollIndicatorsConfigurator: NSViewRepresentable {
    final class Coordinator {
        private weak var scrollView: NSScrollView?
        private weak var observedWindow: NSWindow?
        private var resizeObserver: NSObjectProtocol?
        private var endLiveResizeObserver: NSObjectProtocol?

        deinit {
            removeWindowObservers()
        }

        func scheduleConfigure(for view: NSView) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view else { return }
                self.configure(for: view)
            }
        }

        private func configure(for view: NSView) {
            guard let resolvedScrollView = findEnclosingScrollView(from: view) else {
                return
            }
            if resolvedScrollView !== scrollView {
                scrollView = resolvedScrollView
            }
            applyAutoHidingOverlayScrollerStyle(to: resolvedScrollView)
            observeWindowIfNeeded(window: resolvedScrollView.window, view: view)
        }

        private func applyAutoHidingOverlayScrollerStyle(to scrollView: NSScrollView) {
            scrollView.scrollerStyle = .overlay
            scrollView.autohidesScrollers = true
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
        }

        private func observeWindowIfNeeded(window: NSWindow?, view: NSView) {
            guard observedWindow !== window else { return }
            removeWindowObservers()
            observedWindow = window
            guard let window else { return }

            resizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window,
                queue: .main
            ) { [weak self, weak view] _ in
                guard let self, let view else { return }
                self.scheduleConfigure(for: view)
            }

            endLiveResizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didEndLiveResizeNotification,
                object: window,
                queue: .main
            ) { [weak self, weak view] _ in
                guard let self, let view else { return }
                self.scheduleConfigure(for: view)
            }
        }

        private func removeWindowObservers() {
            if let resizeObserver {
                NotificationCenter.default.removeObserver(resizeObserver)
                self.resizeObserver = nil
            }
            if let endLiveResizeObserver {
                NotificationCenter.default.removeObserver(endLiveResizeObserver)
                self.endLiveResizeObserver = nil
            }
            observedWindow = nil
        }

        private func findEnclosingScrollView(from view: NSView) -> NSScrollView? {
            if let scrollView = view.enclosingScrollView {
                return scrollView
            }

            var current: NSView? = view.superview
            while let node = current {
                if let scrollView = node as? NSScrollView {
                    return scrollView
                }
                if let scrollView = node.enclosingScrollView {
                    return scrollView
                }
                current = node.superview
            }

            return nil
        }
    }

    final class TrackerView: NSView {
        var onHierarchyChange: (() -> Void)?

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            onHierarchyChange?()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onHierarchyChange?()
        }

        override func layout() {
            super.layout()
            onHierarchyChange?()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> TrackerView {
        let view = TrackerView(frame: .zero)
        view.isHidden = true
        view.onHierarchyChange = { [weak coordinator = context.coordinator, weak view] in
            guard let coordinator, let view else { return }
            coordinator.scheduleConfigure(for: view)
        }
        context.coordinator.scheduleConfigure(for: view)
        return view
    }

    func updateNSView(_ nsView: TrackerView, context: Context) {
        context.coordinator.scheduleConfigure(for: nsView)
    }
}

extension View {
    func autoHidingOverlayScrollIndicators() -> some View {
        modifier(AutoHidingOverlayScrollIndicatorsModifier())
    }
}

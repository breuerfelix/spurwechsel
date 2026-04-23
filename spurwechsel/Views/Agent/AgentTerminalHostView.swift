import AppKit
import GhosttyTerminal
import SwiftUI

struct AgentTerminalHostView: NSViewRepresentable {
    let controller: AgentTerminalSessionController
    let terminalTheme: TerminalTheme
    let terminalBackgroundColor: Color
    let isActive: Bool
    let surfaceSlot: SurfaceSlot
    let focusRequest: SurfaceFocusRequest?
    let onSurfaceFocused: (SurfaceSlot) -> Void

    @Environment(\.colorScheme) private var colorScheme

    init(
        controller: AgentTerminalSessionController,
        terminalTheme: TerminalTheme = ThemeSet.default.terminalTheme,
        terminalBackgroundColor: Color = Color(hexString: "#161616"),
        isActive: Bool = true,
        surfaceSlot: SurfaceSlot = .main,
        focusRequest: SurfaceFocusRequest? = nil,
        onSurfaceFocused: @escaping (SurfaceSlot) -> Void = { _ in }
    ) {
        self.controller = controller
        self.terminalTheme = terminalTheme
        self.terminalBackgroundColor = terminalBackgroundColor
        self.isActive = isActive
        self.surfaceSlot = surfaceSlot
        self.focusRequest = focusRequest
        self.onSurfaceFocused = onSurfaceFocused
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(surface: controller.retainedSurface)
    }

    func makeNSView(context: Context) -> RetainedHostedSurfaceContainer<TerminalView> {
        let container = RetainedHostedSurfaceContainer<TerminalView>()
        context.coordinator.surface = controller.retainedSurface
        controller.retainedSurface.attach(to: container)
        applyState(in: container, coordinator: context.coordinator)
        return container
    }

    func updateNSView(_ nsView: RetainedHostedSurfaceContainer<TerminalView>, context: Context) {
        context.coordinator.surface = controller.retainedSurface
        controller.retainedSurface.attach(to: nsView)
        applyState(in: nsView, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ nsView: RetainedHostedSurfaceContainer<TerminalView>, coordinator: Coordinator) {
        coordinator.release(from: nsView)
    }

    private func applyState(
        in container: RetainedHostedSurfaceContainer<TerminalView>,
        coordinator: Coordinator
    ) {
        coordinator.performIfCurrentOwner(in: container) { view in
            view.wantsLayer = true
            view.layer?.isOpaque = false
            view.layer?.backgroundColor = NSColor(terminalBackgroundColor).cgColor
            container.configureFocus(
                slot: surfaceSlot,
                request: focusRequest,
                onSurfaceFocused: onSurfaceFocused
            ) { hostedView in
                guard let window = hostedView.window else {
                    return false
                }
                return window.makeFirstResponder(hostedView)
            }

            _ = controller.terminalState.setTheme(terminalTheme)
            controller.terminalState.adopt(colorScheme: colorScheme)
            view.setSurfaceVisible(isActive)

            if isActive {
                controller.markSurfaceActive()
            } else {
                controller.markSurfaceInactive()
            }
        }

        coordinator.performAsyncIfCurrentOwner(in: container) { view in
            container.needsLayout = true
            container.layoutSubtreeIfNeeded()
            view.needsLayout = true
            view.layoutSubtreeIfNeeded()
            view.needsDisplay = true

            if isActive {
                view.fitToSize()
                view.setSurfaceVisible(true)
            } else {
                view.setSurfaceVisible(false)
            }
        }
    }

    final class Coordinator {
        var surface: RetainedHostedSurface<TerminalView>

        init(surface: RetainedHostedSurface<TerminalView>) {
            self.surface = surface
        }

        func release(from container: RetainedHostedSurfaceContainer<TerminalView>) {
            surface.release(from: container)
        }

        func performIfCurrentOwner(
            in container: RetainedHostedSurfaceContainer<TerminalView>,
            _ update: (TerminalView) -> Void
        ) {
            surface.performIfCurrentOwner(in: container, update)
        }

        func performAsyncIfCurrentOwner(
            in container: RetainedHostedSurfaceContainer<TerminalView>,
            _ update: @escaping (TerminalView) -> Void
        ) {
            surface.performAsyncIfCurrentOwner(in: container, update)
        }
    }
}

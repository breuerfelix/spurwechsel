import SwiftUI
import WebKit

struct EmbeddedWebViewHost: NSViewRepresentable {
    let runtime: EmbeddedWebViewRuntime
    let isActive: Bool
    let surfaceSlot: SurfaceSlot
    let focusRequest: SurfaceFocusRequest?
    let onSurfaceFocused: (SurfaceSlot) -> Void

    init(
        runtime: EmbeddedWebViewRuntime,
        isActive: Bool,
        surfaceSlot: SurfaceSlot = .main,
        focusRequest: SurfaceFocusRequest? = nil,
        onSurfaceFocused: @escaping (SurfaceSlot) -> Void = { _ in }
    ) {
        self.runtime = runtime
        self.isActive = isActive
        self.surfaceSlot = surfaceSlot
        self.focusRequest = focusRequest
        self.onSurfaceFocused = onSurfaceFocused
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(surface: runtime.retainedSurface)
    }

    func makeNSView(context: Context) -> RetainedHostedSurfaceContainer<WKWebView> {
        let container = RetainedHostedSurfaceContainer<WKWebView>()
        context.coordinator.surface = runtime.retainedSurface
        runtime.retainedSurface.attach(to: container)
        applyState(in: container, coordinator: context.coordinator)
        return container
    }

    func updateNSView(_ nsView: RetainedHostedSurfaceContainer<WKWebView>, context: Context) {
        context.coordinator.surface = runtime.retainedSurface
        runtime.retainedSurface.attach(to: nsView)
        applyState(in: nsView, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ nsView: RetainedHostedSurfaceContainer<WKWebView>, coordinator: Coordinator) {
        coordinator.release(from: nsView)
    }

    private func applyState(
        in container: RetainedHostedSurfaceContainer<WKWebView>,
        coordinator: Coordinator
    ) {
        coordinator.performIfCurrentOwner(in: container) { webView in
            webView.isHidden = !isActive
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
        }

        coordinator.performAsyncIfCurrentOwner(in: container) { webView in
            container.needsLayout = true
            container.layoutSubtreeIfNeeded()
            webView.needsLayout = true
            webView.layoutSubtreeIfNeeded()
            webView.needsDisplay = true
            webView.isHidden = !isActive
        }
    }

    final class Coordinator {
        var surface: RetainedHostedSurface<WKWebView>

        init(surface: RetainedHostedSurface<WKWebView>) {
            self.surface = surface
        }

        func release(from container: RetainedHostedSurfaceContainer<WKWebView>) {
            surface.release(from: container)
        }

        func performIfCurrentOwner(
            in container: RetainedHostedSurfaceContainer<WKWebView>,
            _ update: (WKWebView) -> Void
        ) {
            surface.performIfCurrentOwner(in: container, update)
        }

        func performAsyncIfCurrentOwner(
            in container: RetainedHostedSurfaceContainer<WKWebView>,
            _ update: @escaping (WKWebView) -> Void
        ) {
            surface.performAsyncIfCurrentOwner(in: container, update)
        }
    }
}

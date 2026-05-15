import AppKit
import SwiftUI

enum KeyDownInterceptResult {
    case passThrough
    case consume
    case replace(NSEvent)
}

struct WindowActivityObserver: NSViewRepresentable {
    let onWindowKeyChange: (Bool) -> Void
    let onApplicationActiveChange: (Bool) -> Void
    let onKeyDownIntercept: (NSEvent, SurfaceSlot?) -> KeyDownInterceptResult
    let handleWindowCloseRequest: () -> Bool
    let onFocusedSurfaceSlotChange: (SurfaceSlot) -> Void
    let onWindowChromeStateChange: (WindowChromeState) -> Void
    let topBarFrameInWindow: CGRect?
    let isCommandBarPresented: Bool
    let shouldRestoreCommandBarFocus: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onWindowKeyChange: onWindowKeyChange,
            onApplicationActiveChange: onApplicationActiveChange,
            onKeyDownIntercept: onKeyDownIntercept,
            handleWindowCloseRequest: handleWindowCloseRequest,
            onFocusedSurfaceSlotChange: onFocusedSurfaceSlotChange,
            onWindowChromeStateChange: onWindowChromeStateChange,
            isCommandBarPresented: isCommandBarPresented
        )
    }

    func makeNSView(context: Context) -> WindowObserverNSView {
        let view = WindowObserverNSView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: WindowObserverNSView, context: Context) {
        nsView.coordinator = context.coordinator
        context.coordinator.updateWindow(nsView.window)
        context.coordinator.updateTopBarFrame(topBarFrameInWindow)
        context.coordinator.handleApplicationActiveChange(NSApplication.shared.isActive)
        context.coordinator.updateCommandBarState(
            window: nsView.window,
            isPresented: isCommandBarPresented,
            shouldRestoreFocus: shouldRestoreCommandBarFocus
        )
    }

    static func dismantleNSView(_ nsView: WindowObserverNSView, coordinator: Coordinator) {
        coordinator.updateWindow(nil)
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        private enum ChromeMetrics {
            static let trafficLightLeadingPadding: CGFloat = 10
            static let iconGap: CGFloat = SpurSpacing.sm / 2
            static let minimumWindowSize = NSSize(width: 900, height: 620)
        }

        private let onWindowKeyChange: (Bool) -> Void
        private let onApplicationActiveChange: (Bool) -> Void
        private let onKeyDownIntercept: (NSEvent, SurfaceSlot?) -> KeyDownInterceptResult
        private let handleWindowCloseRequest: () -> Bool
        private let onFocusedSurfaceSlotChange: (SurfaceSlot) -> Void
        private let onWindowChromeStateChange: (WindowChromeState) -> Void
        private var isCommandBarPresented: Bool
        private var observedWindow: NSWindow?
        private var topBarFrameInWindow: CGRect?
        private var windowBecomeKeyObserver: NSObjectProtocol?
        private var windowResignKeyObserver: NSObjectProtocol?
        private var windowDidUpdateObserver: NSObjectProtocol?
        private var windowDidResizeObserver: NSObjectProtocol?
        private var windowDidEndLiveResizeObserver: NSObjectProtocol?
        private var windowDidEnterFullScreenObserver: NSObjectProtocol?
        private var windowDidExitFullScreenObserver: NSObjectProtocol?
        private var localKeyMonitor: Any?
        private var lastWindowKeyValue: Bool?
        private var lastApplicationActiveValue: Bool?
        private var lastFocusedSurfaceSlot: SurfaceSlot?
        private var lastWindowChromeState: WindowChromeState?
        private weak var preservedFirstResponder: NSResponder?

        init(
            onWindowKeyChange: @escaping (Bool) -> Void,
            onApplicationActiveChange: @escaping (Bool) -> Void,
            onKeyDownIntercept: @escaping (NSEvent, SurfaceSlot?) -> KeyDownInterceptResult,
            handleWindowCloseRequest: @escaping () -> Bool,
            onFocusedSurfaceSlotChange: @escaping (SurfaceSlot) -> Void,
            onWindowChromeStateChange: @escaping (WindowChromeState) -> Void,
            isCommandBarPresented: Bool
        ) {
            self.onWindowKeyChange = onWindowKeyChange
            self.onApplicationActiveChange = onApplicationActiveChange
            self.onKeyDownIntercept = onKeyDownIntercept
            self.handleWindowCloseRequest = handleWindowCloseRequest
            self.onFocusedSurfaceSlotChange = onFocusedSurfaceSlotChange
            self.onWindowChromeStateChange = onWindowChromeStateChange
            self.isCommandBarPresented = isCommandBarPresented
            super.init()
            installLocalKeyMonitor()
        }

        deinit {
            removeWindowObservers()
            removeLocalKeyMonitor()
        }

        func updateWindow(_ window: NSWindow?) {
            guard observedWindow !== window else {
                if let window {
                    configureWindowChrome(window)
                    syncWindowChrome(in: window)
                }
                return
            }
            removeWindowObservers()
            observedWindow = window
            guard let window else {
                publishWindowChromeState(
                    WindowChromeState(
                        topBarFrameInWindow: topBarFrameInWindow,
                        trafficLightsReservedLeadingWidth: 0,
                        isFullScreen: false
                    )
                )
                return
            }
            window.delegate = self
            configureWindowChrome(window)
            let center = NotificationCenter.default
            windowBecomeKeyObserver = center.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.publishWindowKeyChange(true)
            }
            windowResignKeyObserver = center.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.publishWindowKeyChange(false)
            }
            windowDidUpdateObserver = center.addObserver(
                forName: NSWindow.didUpdateNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.publishFocusedSurfaceSlotIfNeeded(in: window)
                self?.syncWindowChrome(in: window)
            }
            windowDidResizeObserver = center.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.syncWindowChrome(in: window)
            }
            windowDidEndLiveResizeObserver = center.addObserver(
                forName: NSWindow.didEndLiveResizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.syncWindowChrome(in: window)
            }
            windowDidEnterFullScreenObserver = center.addObserver(
                forName: NSWindow.didEnterFullScreenNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.syncWindowChrome(in: window)
            }
            windowDidExitFullScreenObserver = center.addObserver(
                forName: NSWindow.didExitFullScreenNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.syncWindowChrome(in: window)
            }
            publishWindowKeyChange(window.isKeyWindow)
            publishFocusedSurfaceSlotIfNeeded(in: window)
            syncWindowChrome(in: window)
        }

        private func configureWindowChrome(_ window: NSWindow) {
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = false
            window.contentMinSize = ChromeMetrics.minimumWindowSize
            if #available(macOS 11.0, *) {
                window.toolbarStyle = .unifiedCompact
            }
        }

        func updateTopBarFrame(_ frame: CGRect?) {
            guard topBarFrameInWindow != frame else {
                return
            }
            topBarFrameInWindow = frame
            syncWindowChrome(in: observedWindow)
        }

        private func syncWindowChrome(in window: NSWindow?) {
            guard let window else {
                return
            }

            let isFullScreen = window.styleMask.contains(.fullScreen)
            if isFullScreen {
                publishWindowChromeState(
                    WindowChromeState(
                        topBarFrameInWindow: topBarFrameInWindow,
                        trafficLightsReservedLeadingWidth: 0,
                        isFullScreen: true
                    )
                )
                return
            }

            guard let closeButton = window.standardWindowButton(.closeButton),
                  let miniaturizeButton = window.standardWindowButton(.miniaturizeButton),
                  let zoomButton = window.standardWindowButton(.zoomButton),
                  let container = closeButton.superview,
                  let topBarFrameInWindow
            else {
                publishWindowChromeState(
                    WindowChromeState(
                        topBarFrameInWindow: topBarFrameInWindow,
                        trafficLightsReservedLeadingWidth: 0,
                        isFullScreen: false
                    )
                )
                return
            }

            let layout = WindowChromeLayoutResolver.resolveLayout(
                topBarFrameInWindow: topBarFrameInWindow,
                closeButtonFrame: closeButton.frame,
                miniaturizeButtonFrame: miniaturizeButton.frame,
                zoomButtonFrame: zoomButton.frame,
                leadingPadding: ChromeMetrics.trafficLightLeadingPadding,
                iconGap: ChromeMetrics.iconGap
            )

            let closeOrigin = container.convert(layout.closeButtonOrigin, from: nil)
            let miniOrigin = container.convert(layout.miniaturizeButtonOrigin, from: nil)
            let zoomOrigin = container.convert(layout.zoomButtonOrigin, from: nil)

            closeButton.setFrameOrigin(closeOrigin)
            miniaturizeButton.setFrameOrigin(miniOrigin)
            zoomButton.setFrameOrigin(zoomOrigin)

            publishWindowChromeState(
                WindowChromeState(
                    topBarFrameInWindow: topBarFrameInWindow,
                    trafficLightsReservedLeadingWidth: layout.reservedLeadingWidth,
                    isFullScreen: false
                )
            )
        }

        private func publishWindowChromeState(_ state: WindowChromeState) {
            guard lastWindowChromeState != state else {
                return
            }
            lastWindowChromeState = state
            DispatchQueue.main.async { [onWindowChromeStateChange] in
                onWindowChromeStateChange(state)
            }
        }

        func handleApplicationActiveChange(_ isActive: Bool) {
            publishApplicationActiveChange(isActive)
        }

        func updateCommandBarState(
            window: NSWindow?,
            isPresented: Bool,
            shouldRestoreFocus: Bool
        ) {
            let wasPresented = isCommandBarPresented
            isCommandBarPresented = isPresented

            guard let window else {
                if !isPresented {
                    preservedFirstResponder = nil
                }
                return
            }

            if isPresented && !wasPresented {
                preservedFirstResponder = window.firstResponder
                if shouldClearFirstResponderOnCommandBarPresentation(preservedFirstResponder) {
                    _ = window.makeFirstResponder(nil)
                }
                return
            }

            guard !isPresented, wasPresented else {
                return
            }

            let preservedCandidate = shouldRestoreFocus ? preservedFirstResponder : nil
            preservedFirstResponder = nil

            DispatchQueue.main.async { [weak window] in
                guard let window else {
                    return
                }

                if let preservedCandidate,
                   preservedCandidate !== window.firstResponder,
                   window.makeFirstResponder(preservedCandidate) {
                    self.publishFocusedSurfaceSlotIfNeeded(in: window)
                    return
                }
                self.publishFocusedSurfaceSlotIfNeeded(in: window)
            }
        }

        private func publishWindowKeyChange(_ isKey: Bool) {
            guard lastWindowKeyValue != isKey else {
                return
            }
            lastWindowKeyValue = isKey
            DispatchQueue.main.async { [onWindowKeyChange] in
                onWindowKeyChange(isKey)
            }
        }

        private func publishApplicationActiveChange(_ isActive: Bool) {
            guard lastApplicationActiveValue != isActive else {
                return
            }
            lastApplicationActiveValue = isActive
            DispatchQueue.main.async { [onApplicationActiveChange] in
                onApplicationActiveChange(isActive)
            }
        }

        private func removeWindowObservers() {
            if observedWindow?.delegate === self {
                observedWindow?.delegate = nil
            }

            let center = NotificationCenter.default
            if let windowBecomeKeyObserver {
                center.removeObserver(windowBecomeKeyObserver)
            }
            if let windowResignKeyObserver {
                center.removeObserver(windowResignKeyObserver)
            }
            if let windowDidUpdateObserver {
                center.removeObserver(windowDidUpdateObserver)
            }
            if let windowDidResizeObserver {
                center.removeObserver(windowDidResizeObserver)
            }
            if let windowDidEndLiveResizeObserver {
                center.removeObserver(windowDidEndLiveResizeObserver)
            }
            if let windowDidEnterFullScreenObserver {
                center.removeObserver(windowDidEnterFullScreenObserver)
            }
            if let windowDidExitFullScreenObserver {
                center.removeObserver(windowDidExitFullScreenObserver)
            }
            windowBecomeKeyObserver = nil
            windowResignKeyObserver = nil
            windowDidUpdateObserver = nil
            windowDidResizeObserver = nil
            windowDidEndLiveResizeObserver = nil
            windowDidEnterFullScreenObserver = nil
            windowDidExitFullScreenObserver = nil
            observedWindow = nil
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            handleWindowCloseRequest()
        }

        private func installLocalKeyMonitor() {
            guard localKeyMonitor == nil else {
                return
            }

            localKeyMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] event in
                guard let self else {
                    return event
                }
                let focusedSurfaceSlot = self.resolveFocusedSurfaceSlot(in: event.window ?? self.observedWindow)
                let interceptedEvent: NSEvent?
                if event.type == .keyDown {
                    switch self.onKeyDownIntercept(event, focusedSurfaceSlot) {
                    case .passThrough:
                        interceptedEvent = event
                    case .consume:
                        interceptedEvent = nil
                    case let .replace(replacement):
                        interceptedEvent = replacement
                    }
                } else {
                    interceptedEvent = event
                }

                let sourceWindow = event.window ?? self.observedWindow
                if let sourceWindow {
                    DispatchQueue.main.async {
                        self.publishFocusedSurfaceSlotIfNeeded(in: sourceWindow)
                    }
                }

                return interceptedEvent
            }
        }

        private func removeLocalKeyMonitor() {
            guard let localKeyMonitor else {
                return
            }
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }

        private func publishFocusedSurfaceSlotIfNeeded(in window: NSWindow?) {
            guard let focusedSlot = resolveFocusedSurfaceSlot(in: window),
                  focusedSlot != lastFocusedSurfaceSlot
            else {
                return
            }
            lastFocusedSurfaceSlot = focusedSlot
            DispatchQueue.main.async { [onFocusedSurfaceSlotChange] in
                onFocusedSurfaceSlotChange(focusedSlot)
            }
        }

        private func resolveFocusedSurfaceSlot(in window: NSWindow?) -> SurfaceSlot? {
            guard let window else {
                return nil
            }

            guard let responder = window.firstResponder else {
                return nil
            }

            return surfaceSlot(for: responder)
        }

        private func shouldClearFirstResponderOnCommandBarPresentation(_ responder: NSResponder?) -> Bool {
            guard let responder else {
                return false
            }
            return surfaceSlot(for: responder) != nil
        }

        private func surfaceSlot(for responder: NSResponder) -> SurfaceSlot? {
            if let responderView = responder as? NSView {
                return responderView.surfaceSlotInHierarchy()
            }

            if let nextResponderView = responder.nextResponder as? NSView {
                return nextResponderView.surfaceSlotInHierarchy()
            }

            return nil
        }
    }
}

private extension NSView {
    func surfaceSlotInHierarchy() -> SurfaceSlot? {
        var current: NSView? = self
        while let view = current {
            if let trackedView = view as? SurfaceSlotTracking,
               let slot = trackedView.surfaceSlot {
                return slot
            }
            current = view.superview
        }
        return nil
    }
}

final class WindowObserverNSView: NSView {
    weak var coordinator: WindowActivityObserver.Coordinator?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        coordinator?.updateWindow(window)
        coordinator?.handleApplicationActiveChange(NSApplication.shared.isActive)
    }
}

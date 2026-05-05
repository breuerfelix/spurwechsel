import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var store: SpurwechselAppStore

    @MainActor
    init(store: SpurwechselAppStore? = nil) {
        _store = StateObject(wrappedValue: store ?? SpurwechselAppStore())
    }

    var body: some View {
        SpurwechselShellView(store: store)
            .preferredColorScheme(store.layout.themeMode.colorScheme)
            .background(
                WindowActivityObserver(
                    onWindowKeyChange: store.setWindowKey(_:),
                    onApplicationActiveChange: store.setApplicationActive(_:),
                    onKeyDownIntercept: store.handleGlobalShortcutEvent(_:),
                    handleWindowCloseRequest: store.handleWindowCloseRequest,
                    onFocusedSurfaceSlotChange: store.recordFocusedSurfaceSlot(_:),
                    onWindowChromeStateChange: store.setWindowChromeState(_:),
                    topBarFrameInWindow: store.windowChromeState.topBarFrameInWindow,
                    isCommandBarPresented: store.commandBar.isPresented,
                    shouldRestoreCommandBarFocus: store.commandBarShouldRestorePreviousFocus
                )
                .frame(width: 0, height: 0)
            )
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                store.setApplicationActive(true)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                store.setApplicationActive(false)
            }
    }
}

private struct SpurwechselShellView: View {
    @ObservedObject var store: SpurwechselAppStore
    @State private var previewDragStartWidth: CGFloat?

    private var theme: SpurTheme { store.theme }

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                let metrics = ShellMetrics(size: proxy.size, layout: store.layout)
                let previewResizeBounds = ShellMetrics.previewWidthBounds(size: proxy.size, layout: store.layout)
                let showsLeftSidebar = store.layout.effectiveShowsLeftSidebar

                VStack(spacing: 0) {
                    TopBarView(
                        shellStore: store.shellStore,
                        previewModels: store.previewModels,
                        windowChromeState: store.windowChromeState,
                        onTopBarFrameChange: { store.setTopBarFrameInWindow($0) },
                        openCommandBar: { store.send(.openCommandBar(projectContextID: nil, workspaceContext: nil)) },
                        toggleLeftSidebar: { store.send(.toggleLeftSidebar) },
                        toggleRightSidebar: { store.send(.toggleRightSidebar) },
                        togglePreview: { store.send(.togglePreview) },
                        selectMainView: { store.send(.selectMainView($0)) },
                        selectPreviewView: { store.send(.selectPreviewView($0)) }
                    )
                        .padding(.horizontal, metrics.outerPadding)

                    HStack(alignment: .top, spacing: 0) {
                        if showsLeftSidebar {
                            ContextSidebarView(
                                shellStore: store.shellStore,
                                workspaceStore: store.workspaceStore,
                                agentStore: store.agentStore,
                                addAgent: { store.send(.addAgent($0)) },
                                selectSession: { store.send(.selectAgentSession($0)) }
                            )
                                .frame(width: metrics.leftSidebarWidth)
                                .transition(.move(edge: .leading).combined(with: .opacity))

                            panelGap(width: metrics.gap)
                        }

                        mainSurface
                            .frame(
                                minWidth: metrics.mainWidth,
                                maxWidth: .infinity,
                                maxHeight: .infinity
                            )

                        if store.layout.previewEnabled {
                            previewResizeHandle(
                                previewWidth: metrics.previewWidth,
                                allowedRange: previewResizeBounds,
                                handleWidth: metrics.gap
                            )

                            previewSurface
                                .frame(width: metrics.previewWidth)
                                .transition(.move(edge: .trailing).combined(with: .opacity))

                            if store.layout.showsRightSidebar {
                                panelGap(width: metrics.gap)
                            }
                        } else if store.layout.showsRightSidebar {
                            panelGap(width: metrics.gap)
                        }

                        if store.layout.showsRightSidebar {
                            WorkspaceSidebarView(
                                shellStore: store.shellStore,
                                workspaceStore: store.workspaceStore,
                                executeCommand: { store.executeCommand($0) },
                                toggleTheme: { store.send(.toggleTheme) },
                                selectWorkspace: { store.send(.selectWorkspace($0)) },
                                addWorktree: { store.send(.addWorktree($0)) },
                                toggleProjectCollapse: { store.send(.toggleProjectCollapse($0)) }
                            )
                                .frame(width: metrics.rightSidebarWidth)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, metrics.outerPadding)
                    .padding(.bottom, metrics.outerPadding)
                    .padding(.top, 2)
                    .animation(.spring(response: 0.28, dampingFraction: 0.9), value: store.layout.previewEnabled)
                    .animation(.spring(response: 0.28, dampingFraction: 0.9), value: showsLeftSidebar)
                    .animation(.spring(response: 0.28, dampingFraction: 0.9), value: store.layout.showsRightSidebar)
                }

            }

            if store.commandBar.isPresented {
                CommandPaletteOverlayView(store: store.commandPaletteViewStore)
                    .transition(.opacity.combined(with: .scale(scale: 0.99)))
                    .zIndex(5)
            }

            VStack {
                if let configNotification = store.configNotification {
                    ConfigNotificationBannerView(
                        state: configNotification,
                        theme: store.theme,
                        dismiss: store.dismissConfigNotification
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, SpurSpacing.md)
                    .padding(.horizontal, SpurSpacing.md)
                    .zIndex(10)
                }

                Spacer()
            }

            if store.appShutdown.isInProgress {
                AppShutdownOverlayView(state: store.appShutdown, theme: store.theme)
                    .zIndex(20)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(theme.backgroundGradient.ignoresSafeArea())
    }

    @ViewBuilder
    private var mainSurface: some View {
        surfaceSlot(.main, surfaceID: store.mountedMainSurfaceID)
    }

    @ViewBuilder
    private var previewSurface: some View {
        surfaceSlot(.preview, surfaceID: store.mountedPreviewSurfaceID)
    }

    @ViewBuilder
    private func surfaceSlot(_ slot: SurfaceSlot, surfaceID: SurfaceTabID?) -> some View {
        if let surfaceID,
           let tab = store.surfaceTab(for: surfaceID) {
            let isSelected = slot == .main || (slot == .preview && store.layout.previewEnabled)
            surfaceContent(
                for: surfaceID,
                tab: tab,
                slot: slot,
                isSurfaceSelected: isSelected
            )
        } else if surfaceID != nil {
            SurfaceStateView(
                icon: "exclamationmark.triangle",
                title: "Surface unavailable",
                message: "Surface reference exists but no matching tab state found.",
                theme: store.theme,
                emphasis: .error,
                showsPanel: true
            )
            .accessibilityIdentifier(slot == .main ? "surface.main.unavailable" : "surface.preview.unavailable")
        } else {
            if slot == .main && store.projects.projects.isEmpty {
                SurfaceStateView(
                    icon: "folder.badge.plus",
                    title: "No workspace imported",
                    message: "Import a repository to start Agent, Terminal, or VSCode surfaces.",
                    theme: store.theme,
                    emphasis: .info,
                    actionHint: "Command Bar: Add New Project",
                    showsPanel: true
                )
                .accessibilityIdentifier("surface.main.empty")
            } else if slot == .preview {
                SurfaceStateView(
                    icon: "rectangle.slash",
                    title: "Preview unavailable",
                    message: "Current preview view cannot mount for selected workspace.",
                    theme: store.theme,
                    emphasis: .neutral,
                    actionHint: "Pick another preview view or switch workspace",
                    showsPanel: true
                )
                .accessibilityIdentifier("surface.preview.empty")
            } else {
                SurfaceStateView(
                    icon: "rectangle.stack",
                    title: "No surface selected",
                    message: "Select project, view, or session to mount surface.",
                    theme: store.theme,
                    emphasis: .neutral,
                    showsPanel: true
                )
                .accessibilityIdentifier("surface.main.empty")
            }
        }
    }

    @ViewBuilder
    private func surfaceContent(
        for surfaceID: SurfaceTabID,
        tab: SurfaceTab,
        slot: SurfaceSlot,
        isSurfaceSelected: Bool
    ) -> some View {
        switch surfaceID {
        case let .agentSession(sessionID):
            AgentMainView(
                store: store.agentSurfaceStore,
                sessionID: sessionID,
                workspaceSelection: tab.workspaceSelection,
                isSurfaceSelected: isSurfaceSelected,
                surfaceSlot: slot,
                focusRequest: store.surfaceFocusRequest,
                onSurfaceFocused: store.recordFocusedSurfaceSlot(_:)
            )
        case .agentWorkspace:
            AgentMainView(
                store: store.agentSurfaceStore,
                sessionID: nil,
                workspaceSelection: tab.workspaceSelection,
                isSurfaceSelected: isSurfaceSelected,
                surfaceSlot: slot,
                focusRequest: store.surfaceFocusRequest,
                onSurfaceFocused: store.recordFocusedSurfaceSlot(_:)
            )
        case .workspaceTerminal:
            ProjectTerminalMainView(
                store: store.terminalSurfaceStore,
                workspaceSelection: tab.workspaceSelection,
                isSurfaceSelected: isSurfaceSelected,
                surfaceSlot: slot,
                focusRequest: store.surfaceFocusRequest,
                onSurfaceFocused: store.recordFocusedSurfaceSlot(_:)
            )
        case let .vscodeWorkspace(workspaceID):
            VSCodeMainView(
                store: store.editorSurfaceStore,
                workspaceID: workspaceID,
                isSurfaceSelected: isSurfaceSelected,
                surfaceSlot: slot,
                focusRequest: store.surfaceFocusRequest,
                onSurfaceFocused: store.recordFocusedSurfaceSlot(_:)
            )
        }
    }

    private func panelGap(width: CGFloat) -> some View {
        Color.clear
            .frame(width: width, height: 1)
            .accessibilityHidden(true)
    }

    private func previewResizeHandle(
        previewWidth: CGFloat,
        allowedRange: ClosedRange<CGFloat>,
        handleWidth: CGFloat
    ) -> some View {
        Color.clear
            .frame(width: handleWidth)
            .frame(maxHeight: .infinity)
            .padding(.vertical, SpurSpacing.sm)
            .background(Color.black.opacity(0.001))
            .contentShape(Rectangle())
            .modifier(HorizontalResizeCursorModifier())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if previewDragStartWidth == nil {
                            previewDragStartWidth = previewWidth
                        }
                        let startWidth = previewDragStartWidth ?? previewWidth
                        let dragDelta = value.location.x - value.startLocation.x
                        let proposedWidth = startWidth - dragDelta
                        store.setPreferredPreviewWidth(proposedWidth, allowedRange: allowedRange)
                    }
                    .onEnded { _ in
                        previewDragStartWidth = nil
                    }
            )
            .accessibilityIdentifier("preview.resize-handle")
    }
}

private struct HorizontalResizeCursorModifier: ViewModifier {
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

private struct AppShutdownOverlayView: View {
    let state: AppShutdownState
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

private struct ConfigNotificationBannerView: View {
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

private struct WindowActivityObserver: NSViewRepresentable {
    let onWindowKeyChange: (Bool) -> Void
    let onApplicationActiveChange: (Bool) -> Void
    let onKeyDownIntercept: (NSEvent) -> Bool
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
        }

        private let onWindowKeyChange: (Bool) -> Void
        private let onApplicationActiveChange: (Bool) -> Void
        private let onKeyDownIntercept: (NSEvent) -> Bool
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
            onKeyDownIntercept: @escaping (NSEvent) -> Bool,
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

        // Defer store mutations out of NSViewRepresentable updates to avoid
        // SwiftUI's "Publishing changes from within view updates" warning.
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
                let intercepted: Bool
                if event.type == .keyDown {
                    intercepted = self.onKeyDownIntercept(event)
                } else {
                    intercepted = false
                }

                let sourceWindow = event.window ?? self.observedWindow
                if let sourceWindow {
                    DispatchQueue.main.async {
                        self.publishFocusedSurfaceSlotIfNeeded(in: sourceWindow)
                    }
                }

                return intercepted ? nil : event
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

private final class WindowObserverNSView: NSView {
    weak var coordinator: WindowActivityObserver.Coordinator?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        coordinator?.updateWindow(window)
        coordinator?.handleApplicationActiveChange(NSApplication.shared.isActive)
    }
}

private struct ShellMetrics {
    private static let minimumContentWidth: CGFloat = 720
    private static let leftSidebarFraction: CGFloat = 0.21
    private static let rightSidebarFraction: CGFloat = 0.22
    private static let leftSidebarMinWidth: CGFloat = 216
    private static let leftSidebarMaxWidth: CGFloat = 288
    private static let rightSidebarMinWidth: CGFloat = 220
    private static let rightSidebarMaxWidth: CGFloat = 320
    private static let leftSidebarCompressedMinWidth: CGFloat = 180
    private static let rightSidebarCompressedMinWidth: CGFloat = 180
    private static let minimumMainWidthForCompression: CGFloat = 360
    private static let absoluteMinimumMainWidth: CGFloat = 320
    private static let minimumPreviewWidth: CGFloat = 260
    private static let defaultPreviewMinWidth: CGFloat = 300
    private static let defaultPreviewMaxWidth: CGFloat = 460

    let outerPadding: CGFloat
    let gap: CGFloat
    let leftSidebarWidth: CGFloat
    let previewWidth: CGFloat
    let rightSidebarWidth: CGFloat
    let mainWidth: CGFloat

    init(size: CGSize, layout: AppLayoutState) {
        let compact = size.width < 1380
        outerPadding = compact ? SpurSpacing.sm : SpurSpacing.md
        gap = compact ? SpurSpacing.sm : SpurSpacing.md

        let panelCount = [
            layout.effectiveShowsLeftSidebar,
            layout.previewEnabled,
            layout.showsRightSidebar
        ].filter { $0 }.count

        let contentWidth = Self.contentWidth(
            size: size,
            outerPadding: outerPadding,
            gap: gap,
            panelCount: panelCount
        )

        var left = layout.effectiveShowsLeftSidebar
            ? Self.clamp(contentWidth * Self.leftSidebarFraction, min: Self.leftSidebarMinWidth, max: Self.leftSidebarMaxWidth)
            : 0

        var right = layout.showsRightSidebar
            ? Self.clamp(contentWidth * Self.rightSidebarFraction, min: Self.rightSidebarMinWidth, max: Self.rightSidebarMaxWidth)
            : 0

        var preview: CGFloat = 0
        if layout.previewEnabled {
            let defaultPreviewWidth = Self.clamp(
                contentWidth * 0.30,
                min: Self.defaultPreviewMinWidth,
                max: Self.defaultPreviewMaxWidth
            )
            let requestedPreviewWidth = layout.preferredPreviewWidth ?? defaultPreviewWidth
            let previewBounds = Self.previewWidthBounds(
                size: size,
                layout: layout,
                outerPadding: outerPadding,
                gap: gap
            )
            preview = Self.clamp(requestedPreviewWidth, min: previewBounds.lowerBound, max: previewBounds.upperBound)
        }

        let minimumPanelsWidth = max(contentWidth - Self.minimumMainWidthForCompression, 0)
        let panelWidthTotal = left + preview + right
        if panelWidthTotal > minimumPanelsWidth {
            var deficit = panelWidthTotal - minimumPanelsWidth

            let rightSlack = max(right - Self.rightSidebarCompressedMinWidth, 0)
            let rightReduction = min(deficit, rightSlack)
            right -= rightReduction
            deficit -= rightReduction

            let leftSlack = max(left - Self.leftSidebarCompressedMinWidth, 0)
            let leftReduction = min(deficit, leftSlack)
            left -= leftReduction
            deficit -= leftReduction

            let previewSlack = max(preview - Self.minimumPreviewWidth, 0)
            let previewReduction = min(deficit, previewSlack)
            preview -= previewReduction
        }

        let main = contentWidth - left - preview - right

        leftSidebarWidth = left
        previewWidth = preview
        rightSidebarWidth = right
        mainWidth = max(main, Self.absoluteMinimumMainWidth)
    }

    static func previewWidthBounds(size: CGSize, layout: AppLayoutState) -> ClosedRange<CGFloat> {
        let compact = size.width < 1380
        let outerPadding = compact ? SpurSpacing.sm : SpurSpacing.md
        let gap = compact ? SpurSpacing.sm : SpurSpacing.md
        return previewWidthBounds(size: size, layout: layout, outerPadding: outerPadding, gap: gap)
    }

    private static func previewWidthBounds(
        size: CGSize,
        layout: AppLayoutState,
        outerPadding: CGFloat,
        gap: CGFloat
    ) -> ClosedRange<CGFloat> {
        guard layout.previewEnabled else {
            return minimumPreviewWidth...minimumPreviewWidth
        }

        let panelCount = [
            layout.effectiveShowsLeftSidebar,
            layout.previewEnabled,
            layout.showsRightSidebar
        ].filter { $0 }.count

        let contentWidth = contentWidth(
            size: size,
            outerPadding: outerPadding,
            gap: gap,
            panelCount: panelCount
        )

        let left = layout.effectiveShowsLeftSidebar
            ? clamp(contentWidth * leftSidebarFraction, min: leftSidebarMinWidth, max: leftSidebarMaxWidth)
            : 0
        let right = layout.showsRightSidebar
            ? clamp(contentWidth * rightSidebarFraction, min: rightSidebarMinWidth, max: rightSidebarMaxWidth)
            : 0

        var maxPreview = contentWidth - left - right - minimumMainWidthForCompression
        maxPreview += max(right - rightSidebarCompressedMinWidth, 0)
        maxPreview += max(left - leftSidebarCompressedMinWidth, 0)
        maxPreview = max(maxPreview, minimumPreviewWidth)

        return minimumPreviewWidth...maxPreview
    }

    private static func contentWidth(
        size: CGSize,
        outerPadding: CGFloat,
        gap: CGFloat,
        panelCount: Int
    ) -> CGFloat {
        max(size.width - (outerPadding * 2) - (CGFloat(panelCount + 1) * gap), minimumContentWidth)
    }

    private static func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, min), max)
    }
}

struct ContentView_Previews: PreviewProvider {
    @MainActor
    static var previews: some View {
        Group {
            ContentView(store: agentCompactStore)
                .previewDisplayName("Dark / Agent Compact")

            ContentView(store: terminalStore)
                .previewDisplayName("Dark / Terminal")

            ContentView(store: vscodeIdleStore)
                .previewDisplayName("Dark / VSCode Idle")

            ContentView(store: vscodeStartingStore)
                .previewDisplayName("Dark / VSCode Starting")

            ContentView(store: vscodeRunningStore)
                .previewDisplayName("Dark / VSCode Running")

            ContentView(store: vscodeStoppedStore)
                .previewDisplayName("Dark / VSCode Stopped")

            ContentView(store: vscodeFailureStore)
                .previewDisplayName("Dark / VSCode Failure")
        }
        .frame(width: 1560, height: 940)
    }

    @MainActor
    private static var agentCompactStore: SpurwechselAppStore {
        let store = SpurwechselAppStore()
        store.layout.selectedMainView = .agent
        return store
    }

    @MainActor
    private static var terminalStore: SpurwechselAppStore {
        let store = SpurwechselAppStore()
        store.layout.selectedMainView = .terminal
        return store
    }

    @MainActor
    private static var vscodeIdleStore: SpurwechselAppStore {
        let store = SpurwechselAppStore(vscodeServer: PreviewFixtures.vscodeIdleState)
        store.layout.selectedMainView = .vscode
        return store
    }

    @MainActor
    private static var vscodeStartingStore: SpurwechselAppStore {
        let store = SpurwechselAppStore(vscodeServer: PreviewFixtures.vscodeStartingState)
        store.layout.selectedMainView = .vscode
        return store
    }

    @MainActor
    private static var vscodeRunningStore: SpurwechselAppStore {
        let store = SpurwechselAppStore(vscodeServer: PreviewFixtures.vscodeRunningState)
        store.layout.selectedMainView = .vscode
        return store
    }

    @MainActor
    private static var vscodeStoppedStore: SpurwechselAppStore {
        let store = SpurwechselAppStore(vscodeServer: PreviewFixtures.vscodeStoppedState)
        store.layout.selectedMainView = .vscode
        return store
    }

    @MainActor
    private static var vscodeFailureStore: SpurwechselAppStore {
        let store = SpurwechselAppStore(vscodeServer: PreviewFixtures.vscodeFailureState)
        store.layout.selectedMainView = .vscode
        return store
    }
}

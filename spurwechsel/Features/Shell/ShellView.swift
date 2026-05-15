import ComposableArchitecture
import SwiftUI

struct SpurwechselShellView: View {
    @Environment(\.shellSceneBridge) private var shellSceneBridge
    let shellStore: StoreOf<ShellFeature>
    let workbenchStore: StoreOf<WorkbenchFeature>
    let workspaceStore: StoreOf<WorkspaceFeature>
    let agentStore: StoreOf<AgentFeature>
    let editorStore: StoreOf<EditorFeature>
    let commandPaletteStore: StoreOf<CommandPaletteFeature>
    let lifecycleStore: StoreOf<LifecycleFeature>
    let invokeCommand: (CommandID, UUID?, WorkspaceSelection?) -> Void
    @State private var leftSidebarDragStartWidth: CGFloat?
    @State private var previewDragStartWidth: CGFloat?
    @State private var rightSidebarDragStartWidth: CGFloat?

    private var shell: ShellFeature.State { shellStore.state }
    private var workbench: WorkbenchFeature.State { workbenchStore.state }
    private var workspace: WorkspaceFeature.State { workspaceStore.state }
    private var agent: AgentFeature.State { agentStore.state }
    private var agents: AgentState { agent.agents }
    private var theme: SpurTheme { shell.themeSet.spurTheme(for: shell.layout.themeMode) }
    private var projects: ProjectsState { workspace.projects }

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                let layoutPolicy = ShellLayoutPolicy(size: proxy.size, layout: shell.layout)

                VStack(spacing: 0) {
                    TopBarView(
                        layout: shell.layout,
                        theme: theme,
                        previewModels: PreviewFixtures.previewModels,
                        windowChromeState: shell.windowChrome,
                        onTopBarFrameChange: handleTopBarFrameChange(_:),
                        openCommandBar: openCommandBar,
                        toggleLeftSidebar: toggleLeftSidebar,
                        toggleRightSidebar: toggleRightSidebar,
                        togglePreview: togglePreview,
                        selectMainView: selectMainView(_:),
                        selectPreviewView: selectPreviewView(_:)
                    )
                    .padding(.horizontal, layoutPolicy.outerPadding)

                    HStack(alignment: .top, spacing: 0) {
                        if layoutPolicy.showsLeftSidebar {
                            ContextSidebarView(
                                projects: projects,
                                agents: agents,
                                selectedMainView: shell.layout.selectedMainView,
                                theme: theme,
                                addAgent: addAgent(to:),
                                selectSession: selectSession(_:)
                            )
                            .frame(width: layoutPolicy.leftSidebarWidth)
                            .transition(.move(edge: .leading).combined(with: .opacity))

                            LeftSidebarResizeHandle(
                                width: layoutPolicy.leftSidebarWidth,
                                allowedRange: layoutPolicy.leftSidebarWidthBounds,
                                handleWidth: layoutPolicy.gap,
                                dragStartWidth: $leftSidebarDragStartWidth,
                                onWidthChanged: { proposedWidth, allowedRange in
                                    shellStore.send(.setPreferredLeftSidebarWidth(proposedWidth, allowedRange))
                                },
                                onDragEnded: {
                                    shellStore.send(.persistLayout)
                                }
                            )
                        }

                        mainSurface
                            .frame(
                                minWidth: layoutPolicy.mainWidth,
                                maxWidth: .infinity,
                                maxHeight: .infinity
                            )

                        if layoutPolicy.showsPreview {
                            PreviewResizeHandle(
                                width: layoutPolicy.previewWidth,
                                allowedRange: layoutPolicy.previewWidthBounds,
                                handleWidth: layoutPolicy.gap,
                                dragStartWidth: $previewDragStartWidth,
                                onWidthChanged: { proposedWidth, allowedRange in
                                    shellStore.send(.setPreferredPreviewWidth(proposedWidth, allowedRange))
                                }
                            )

                            previewSurface
                                .frame(width: layoutPolicy.previewWidth)
                                .transition(.move(edge: .trailing).combined(with: .opacity))

                            if layoutPolicy.showsRightSidebar {
                                RightSidebarResizeHandle(
                                    width: layoutPolicy.rightSidebarWidth,
                                    allowedRange: layoutPolicy.rightSidebarWidthBounds,
                                    handleWidth: layoutPolicy.gap,
                                    dragStartWidth: $rightSidebarDragStartWidth,
                                    onWidthChanged: { proposedWidth, allowedRange in
                                        shellStore.send(.setPreferredRightSidebarWidth(proposedWidth, allowedRange))
                                    },
                                    onDragEnded: {
                                        shellStore.send(.persistLayout)
                                    }
                                )
                            }
                        } else if layoutPolicy.showsRightSidebar {
                            RightSidebarResizeHandle(
                                width: layoutPolicy.rightSidebarWidth,
                                allowedRange: layoutPolicy.rightSidebarWidthBounds,
                                handleWidth: layoutPolicy.gap,
                                dragStartWidth: $rightSidebarDragStartWidth,
                                onWidthChanged: { proposedWidth, allowedRange in
                                    shellStore.send(.setPreferredRightSidebarWidth(proposedWidth, allowedRange))
                                },
                                onDragEnded: {
                                    shellStore.send(.persistLayout)
                                }
                            )
                        }

                        if layoutPolicy.showsRightSidebar {
                            WorkspaceSidebarView(
                                store: workspaceStore,
                                projects: projects,
                                theme: theme,
                                selectedThemeMode: shell.layout.themeMode,
                                executeCommand: executeCommand(_:),
                                toggleTheme: toggleTheme,
                                addWorktree: addWorktree(to:)
                            )
                            .frame(width: layoutPolicy.rightSidebarWidth)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, layoutPolicy.outerPadding)
                    .padding(.bottom, layoutPolicy.outerPadding)
                    .padding(.top, 2)
                    .animation(.spring(response: 0.28, dampingFraction: 0.9), value: layoutPolicy.showsPreview)
                    .animation(.spring(response: 0.28, dampingFraction: 0.9), value: layoutPolicy.showsLeftSidebar)
                    .animation(.spring(response: 0.28, dampingFraction: 0.9), value: layoutPolicy.showsRightSidebar)
                }
            }

            ShellOverlayHost(
                shellStore: shellStore,
                commandPaletteStore: commandPaletteStore,
                projects: projects,
                theme: theme,
                configNotification: shell.configNotification,
                shortcutBinding: { command in
                    shell.resolvedShortcuts.first(where: { $0.command == command })
                },
                dismissConfigNotification: dismissConfigNotification
            )
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(theme.backgroundGradient.ignoresSafeArea())
    }

    @ViewBuilder
    private var mainSurface: some View {
        ShellSurfaceSlotView(
            slot: .main,
            surfaceID: workbench.surfaceMountState.mainSurfaceID,
            shell: shell,
            workbench: workbench,
            projects: projects,
            agents: agent.agents,
            editorStore: editorStore,
            theme: theme,
            terminalTheme: shell.themeSet.terminalTheme,
            terminalSurfacesAreForeground: lifecycleStore.state.terminalSurfacesAreForeground,
            agentTerminalController: { sessionID in
                shellSceneBridge.agentTerminalController(sessionID)
            },
            workspaceTerminalController: { workspaceSelection in
                guard let workingDirectory = projects.path(for: workspaceSelection) else {
                    return nil
                }
                return shellSceneBridge.workspaceTerminalController(
                    workspaceSelection.stableID,
                    workingDirectory,
                    shell.themeSet.terminalTheme
                )
            },
            vscodeRuntime: { workspaceID in
                shellSceneBridge.webRuntimeIfPrepared(workspaceID)
            },
            onSurfaceFocused: handleSurfaceFocused(_:)
        )
    }

    @ViewBuilder
    private var previewSurface: some View {
        ShellSurfaceSlotView(
            slot: .preview,
            surfaceID: workbench.surfaceMountState.previewSurfaceID,
            shell: shell,
            workbench: workbench,
            projects: projects,
            agents: agent.agents,
            editorStore: editorStore,
            theme: theme,
            terminalTheme: shell.themeSet.terminalTheme,
            terminalSurfacesAreForeground: lifecycleStore.state.terminalSurfacesAreForeground,
            agentTerminalController: { sessionID in
                shellSceneBridge.agentTerminalController(sessionID)
            },
            workspaceTerminalController: { workspaceSelection in
                guard let workingDirectory = projects.path(for: workspaceSelection) else {
                    return nil
                }
                return shellSceneBridge.workspaceTerminalController(
                    workspaceSelection.stableID,
                    workingDirectory,
                    shell.themeSet.terminalTheme
                )
            },
            vscodeRuntime: { workspaceID in
                shellSceneBridge.webRuntimeIfPrepared(workspaceID)
            },
            onSurfaceFocused: handleSurfaceFocused(_:)
        )
    }

    private func dismissConfigNotification() {
        shellStore.send(.dismissConfigNotification)
    }

    private func handleTopBarFrameChange(_ frame: CGRect?) {
        shellStore.send(.setTopBarFrameInWindow(frame))
    }

    private func openCommandBar() {
        commandPaletteStore.send(.open(projectContextID: nil, workspaceContext: nil))
        shellStore.send(.setCommandBarFocusRestore(true))
    }

    private func toggleLeftSidebar() {
        shellStore.send(.toggleLeftSidebar)
    }

    private func toggleRightSidebar() {
        shellStore.send(.toggleRightSidebar)
    }

    private func togglePreview() {
        shellStore.send(.togglePreview)
    }

    private func selectMainView(_ view: MainViewKind) {
        shellStore.send(.selectMainView(view))
    }

    private func selectPreviewView(_ view: PreviewViewKind) {
        shellStore.send(.selectPreviewView(view))
    }

    private func addAgent(to selection: WorkspaceSelection) {
        invokeCommand(
            .createAgent,
            nil,
            selection
        )
    }

    private func selectSession(_ sessionID: UUID) {
        agentStore.send(.selectSession(sessionID))
    }

    private func executeCommand(_ command: CommandID) {
        invokeCommand(
            command,
            nil,
            nil
        )
    }

    private func toggleTheme() {
        shellStore.send(.toggleTheme)
    }

    private func addWorktree(to projectID: UUID) {
        invokeCommand(
            .addWorktree,
            projectID,
            nil
        )
    }

    private func handleSurfaceFocused(_ slot: SurfaceSlot) {
        shellStore.send(.rememberFocusedSlot(slot))
    }
}

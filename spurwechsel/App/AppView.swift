import ComposableArchitecture
import SwiftUI

struct AppView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        let shellStore = store.scope(state: \.shell, action: \.shell)
        let workbenchStore = store.scope(state: \.workbench, action: \.workbench)
        let workspaceStore = store.scope(state: \.workspace, action: \.workspace)
        let agentStore = store.scope(state: \.agent, action: \.agent)
        let editorStore = store.scope(state: \.editor, action: \.editor)
        let commandPaletteStore = store.scope(state: \.commandPalette, action: \.commandPalette)
        let lifecycleStore = store.scope(state: \.lifecycle, action: \.lifecycle)

        let shell = shellStore.state
        let commandBar = commandPaletteStore.state.commandBar
        let theme = shell.themeSet.spurTheme(for: shell.layout.themeMode)
        let lifecycle = lifecycleStore.state

        ZStack {
            ShellRootView(
                shellStore: shellStore,
                workbenchStore: workbenchStore,
                workspaceStore: workspaceStore,
                agentStore: agentStore,
                editorStore: editorStore,
                commandPaletteStore: commandPaletteStore,
                lifecycleStore: lifecycleStore,
                invokeCommand: { command, projectContextID, workspaceContext in
                    store.send(.invokeCommand(
                        command,
                        projectContextID: projectContextID,
                        workspaceContext: workspaceContext
                    ))
                }
            )

            AppWindowBridge(
                topBarFrameInWindow: shell.windowChrome.topBarFrameInWindow,
                isCommandBarPresented: commandBar.isPresented,
                shouldRestoreCommandBarFocus: shell.commandBarShouldRestorePreviousFocus,
                shortcutBindings: shell.resolvedShortcuts,
                terminalConfig: shell.terminalConfig,
                dispatchShortcut: { command in
                    store.send(.shortcut(command))
                }
            )

            if lifecycle.shutdownPresentation.isVisible {
                AppShutdownOverlayView(
                    state: lifecycle.shutdownPresentation,
                    theme: theme
                )
                .zIndex(20)
                .transition(.opacity)
            }
        }
    }
}

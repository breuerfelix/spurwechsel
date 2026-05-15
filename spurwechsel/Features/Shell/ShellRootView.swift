import ComposableArchitecture
import Foundation
import SwiftUI

struct ShellRootView: View {
    let shellStore: StoreOf<ShellFeature>
    let workbenchStore: StoreOf<WorkbenchFeature>
    let workspaceStore: StoreOf<WorkspaceFeature>
    let agentStore: StoreOf<AgentFeature>
    let editorStore: StoreOf<EditorFeature>
    let commandPaletteStore: StoreOf<CommandPaletteFeature>
    let lifecycleStore: StoreOf<LifecycleFeature>
    let activeVoiceInputSessionID: UUID?
    let invokeCommand: (CommandID, UUID?, WorkspaceSelection?) -> Void

    var body: some View {
        SpurwechselShellView(
            shellStore: shellStore,
            workbenchStore: workbenchStore,
            workspaceStore: workspaceStore,
            agentStore: agentStore,
            editorStore: editorStore,
            commandPaletteStore: commandPaletteStore,
            lifecycleStore: lifecycleStore,
            activeVoiceInputSessionID: activeVoiceInputSessionID,
            invokeCommand: invokeCommand
        )
        .preferredColorScheme(shellStore.state.layout.themeMode.colorScheme)
    }
}

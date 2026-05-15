import AppKit
import GhosttyTerminal
import SwiftUI

struct ShellSceneBridge {
    var agentTerminalController: (UUID) -> AgentTerminalSessionController?
    var workspaceTerminalController: (
        _ workspaceID: String,
        _ workingDirectory: String,
        _ terminalTheme: TerminalTheme
    ) -> LocalShellTerminalSessionController
    var webRuntimeIfPrepared: (String) -> EmbeddedWebViewRuntime?
}

extension ShellSceneBridge {
    static let unimplemented = ShellSceneBridge(
        agentTerminalController: { _ in
            fatalError("ShellSceneBridge.agentTerminalController dependency not configured.")
        },
        workspaceTerminalController: { _, _, _ in
            fatalError("ShellSceneBridge.workspaceTerminalController dependency not configured.")
        },
        webRuntimeIfPrepared: { _ in
            fatalError("ShellSceneBridge.webRuntimeIfPrepared dependency not configured.")
        }
    )
}

private struct ShellSceneBridgeKey: EnvironmentKey {
    static var defaultValue: ShellSceneBridge = .unimplemented
}

extension EnvironmentValues {
    var shellSceneBridge: ShellSceneBridge {
        get { self[ShellSceneBridgeKey.self] }
        set { self[ShellSceneBridgeKey.self] = newValue }
    }
}
